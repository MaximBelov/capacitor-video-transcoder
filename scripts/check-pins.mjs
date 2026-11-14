#!/usr/bin/env node
/* eslint-disable no-console */
// Media3, the Android library the transcoder is built on, is pinned exactly in android/build.gradle, in an `ext` default that
// Dependabot does not read. This compares the pin with the latest stable release on Google's Maven repository (alphas, betas and
// release candidates are skipped) and says whether it is behind. `--pr` also opens a pull request that moves the pin when it is behind, a
// major release included (the pull request is what says what a major breaks), and starts CI on its branch.
//
//   node scripts/check-pins.mjs                 print where the pin stands
//   node scripts/check-pins.mjs --pr            the same, and open a pull request when it is behind (needs git, `gh`, GH_TOKEN)
//   node scripts/check-pins.mjs --pr --dry-run  the same, writing nothing: it says what it would write and run
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

/** The branch a pull request goes to. */
const BASE = 'main';

/** Who the commit is from: the Actions bot, so it is not taken for the person who merges it. */
const BOT = ['-c', 'user.name=github-actions[bot]', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com'];

const VERSION = /^\d+\.\d+\.\d+$/;

/**
 * The SDKs: where each is pinned and where its releases are. `followers` are the files that have to name the same version. iOS has
 * nothing to pin: it uses AVFoundation, which comes with the system.
 */
export const SDKS = [
  {
    name: 'Media3',
    platform: 'Android',
    maven: 'https://dl.google.com/android/maven2/androidx/media3/media3-transformer/maven-metadata.xml',
    notes: (version) => `https://github.com/androidx/media/releases/tag/${version}`,
    file: 'android/build.gradle',
    pin: /media3Version = project\.hasProperty\('media3Version'\) \? rootProject\.ext\.media3Version : '([\d.]+)'/,
    followers: [],
  },
];

const readRoot = (file) => readFileSync(join(root, file), 'utf8');

/** The version a pin names, read out of the file that holds it. */
export function readPin(sdk, read = readRoot) {
  const version = sdk.pin.exec(read(sdk.file))?.[1];
  if (!version) {
    throw new Error(`${sdk.file} names no version for ${sdk.name}`);
  }
  return version;
}

/** Negative when a is older than b, zero when they are the same, positive when a is newer: numeric, so 0.9.9 is older than 0.9.20. */
export function compareVersions(a, b) {
  const [x, y] = [a, b].map((version) => version.split('.').map(Number));
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const order = (x[i] ?? 0) - (y[i] ?? 0);
    if (order !== 0) {
      return order;
    }
  }
  return 0;
}

/** A release tag as a version. Anything but three numbers is refused: it goes into a branch name, a file and a title. */
export function versionOf(tag) {
  const version = tag.replace(/^v/, '');
  if (!VERSION.test(version)) {
    throw new Error(`the release tag ${JSON.stringify(tag)} is not a version of three numbers`);
  }
  return version;
}

/** The newest stable version a Maven metadata file lists: one of three numbers, so 1.12.0-alpha01 and 1.11.0-rc02 are passed over. */
export function latestStable(metadata) {
  const versions = [...metadata.matchAll(/<version>([^<]+)<\/version>/g)].map((m) => m[1]).filter((v) => VERSION.test(v));
  if (versions.length === 0) {
    throw new Error('the Maven metadata lists no stable version');
  }
  return versions.sort(compareVersions).at(-1);
}

/** Where a pin stands against the latest release, and what a pull request that moves it is called. */
export function assess(sdk, pinned, latest) {
  const behind = compareVersions(pinned, latest) < 0;
  return {
    sdk: sdk.name,
    pinned,
    latest,
    behind,
    major: behind && Number(latest.split('.')[0]) > Number(pinned.split('.')[0]),
    line: `${sdk.name}: pinned ${pinned}, latest ${latest}${behind ? ' (behind)' : ''}`,
    title: `Take ${sdk.name} ${latest}`,
    branch: `pin-${sdk.name}-${latest}`,
  };
}

/** Every version a pattern captures in a text, moved from one version to another; one that is not the version being moved is an error. */
function movePin(text, file, pin, from, to) {
  let moved = '';
  let last = 0;
  for (const match of text.matchAll(new RegExp(pin.source, 'gd'))) {
    const [start, end] = match.indices[1];
    if (match[1] !== from) {
      throw new Error(`${file} pins ${match[1]}, not ${from}`);
    }
    moved += text.slice(last, start) + to;
    last = end;
  }
  return moved + text.slice(last);
}

/**
 * Moves a pin, and every file that has to agree with it, from one version to another, through `read` and `write`, and says which
 * files it wrote. A file that does not change is an error, so a format that drifted away from what is looked for cannot pass as a
 * bump that did nothing.
 */
export function bump(sdk, from, to, { read, write }) {
  const written = [];
  for (const { file, pin } of [sdk, ...sdk.followers]) {
    const before = read(file);
    const after = movePin(before, file, pin, from, to);
    if (after === before) {
      throw new Error(`${file} did not change: it names no ${sdk.name} version to move`);
    }
    write(file, after);
    written.push(file);
  }
  return written;
}

const releaseNotes = (sdk, result) => sdk.notes(result.latest);

/** The description of a pull request for a bump that wrote these files; `run` is the link to the CI run started on its branch. */
export function describePullRequest(sdk, result, files, run) {
  return [
    `${sdk.name} ${result.latest} is out, and this plugin pinned ${result.pinned}: ${releaseNotes(sdk, result)}`,
    `This moves the pin in ${files.join(' and ')}. What the release changes for this plugin is for whoever merges this to read in its notes.`,
    ...(result.major
      ? ['This is a major release, so it can change the API this plugin calls: a red check is the first thing to expect. The branch is an ordinary one, and the fix goes on it.']
      : []),
    run
      ? `CI was started on the branch by the workflow, as a workflow_dispatch of ci.yaml that tests everything and never publishes: ${run}. GitHub holds the pull_request run of a pull request that a workflow opened until someone approves it, so the list of checks on this page may not show CI: that run is the CI of this branch.`
      : 'CI was started on the branch by the workflow, as a workflow_dispatch of ci.yaml that tests everything and never publishes: look for it under Actions, on this branch.',
  ].join('\n\n');
}

/** Whether a pull request is to be opened, and if not, why not. A pull request of any state counts: closing one declines the version. */
export function decide(result, pulls) {
  if (!result.behind) {
    return { open: false, why: `${result.sdk} is not behind` };
  }
  const known = pulls.find((pull) => pull.title === result.title || pull.headRefName === result.branch);
  if (known) {
    return { open: false, why: `${result.title}: #${known.number} is already there (${known.state.toLowerCase()})` };
  }
  return { open: true };
}

/** The open pull requests of this script for an older release of the same SDK: they are replaced by the new one. */
export function superseded(result, pulls) {
  return pulls.filter((pull) => pull.state === 'OPEN' && pull.headRefName.startsWith(`pin-${result.sdk}-`) && pull.headRefName !== result.branch);
}

/**
 * Opens a pull request for each SDK that is behind, unless there is one for that version already. `exec` runs what only reads, `act` what
 * writes (and says what it would, in a dry run), `files` reads and writes the working tree. `head` is where each branch starts from.
 */
export function propose(entries, { exec, act, files, head }) {
  const pulls = JSON.parse(exec('gh', ['pr', 'list', '--state', 'all', '--limit', '100', '--json', 'number,title,state,headRefName']));
  for (const { sdk, result } of entries) {
    const verdict = decide(result, pulls);
    if (!verdict.open) {
      console.log(verdict.why);
      continue;
    }
    act('git', ['switch', '--create', result.branch]);
    const written = bump(sdk, result.pinned, result.latest, files);
    act('git', ['add', '--', ...written]);
    act('git', [...BOT, 'commit', '--message', result.title, '--message', `Release notes: ${releaseNotes(sdk, result)}`]);
    act('git', ['push', '--set-upstream', 'origin', result.branch]);
    // CI before the pull request, so that its description can link to the run
    const started = act('gh', ['workflow', 'run', 'ci.yaml', '--ref', result.branch]);
    const run = /https:\/\/github\.com\/\S+\/actions\/runs\/\d+/.exec(started)?.[0];
    const body = describePullRequest(sdk, result, written, run);
    const created = act('gh', ['pr', 'create', '--base', BASE, '--head', result.branch, '--title', result.title, '--body', body]);
    const number = /\/pull\/(\d+)/.exec(created)?.[1];
    for (const old of superseded(result, pulls)) {
      act('gh', ['pr', 'close', String(old.number), '--delete-branch', '--comment', `Replaced by ${number ? `#${number}` : result.title}.`]);
    }
    act('git', ['switch', '--detach', head]);
  }
}

/** The latest stable version on a Maven repository. */
async function latestRelease(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Maven answered ${response.status} for ${url}`);
  }
  return latestStable(await response.text());
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const unknown = args.filter((arg) => arg !== '--pr' && arg !== '--dry-run');
  if (unknown.length > 0 || (args.includes('--dry-run') && !args.includes('--pr'))) {
    throw new Error(`usage: check-pins.mjs [--pr [--dry-run]] (got ${args.join(' ') || 'nothing'})`);
  }
  const dry = args.includes('--dry-run');
  const entries = [];
  for (const sdk of SDKS) {
    const result = assess(sdk, readPin(sdk), await latestRelease(sdk.maven));
    console.log(result.line);
    entries.push({ sdk, result });
  }
  if (args.includes('--pr')) {
    const exec = (command, argv) => execFileSync(command, argv, { cwd: root, encoding: 'utf8' });
    const quote = (arg) => (/^[\w./:=@+-]+$/.test(arg) ? arg : JSON.stringify(arg));
    const act = dry
      ? (command, argv) => {
          console.log(`would run: ${[command, ...argv].map(quote).join(' ')}`);
          return '';
        }
      : (command, argv) => {
          const output = exec(command, argv);
          process.stdout.write(output);
          return output;
        };
    const files = {
      read: readRoot,
      write: dry ? (file) => console.log(`would write: ${file}`) : (file, text) => writeFileSync(join(root, file), text),
    };
    propose(entries, { exec, act, files, head: exec('git', ['rev-parse', 'HEAD']).trim() });
  }
}
