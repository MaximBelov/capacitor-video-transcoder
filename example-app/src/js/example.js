import { Capacitor } from '@capacitor/core';
import { Directory, Encoding, Filesystem } from '@capacitor/filesystem';
import { VideoTranscoder } from 'capacitor-plugin-video-transcoder';

// The device check of the plugin: every video in in/ is transcoded into out/, then the error cases are run, and everything is
// written to out/results.json, which the person checking reads back from the phone (devicectl or adb) together with the MP4s.
const platform = Capacitor.getPlatform();
const directory = platform === 'ios' ? Directory.Documents : Directory.External;
const appId = 'io.github.maximbelov.videotranscoder.example';

const logElement = document.getElementById('log');
const progressElement = document.getElementById('progress');
function log(line) {
  logElement.textContent += `${line}\n`;
  console.log(`[transcode-check] ${line}`);
}

const uriOf = async (path) => (await Filesystem.getUri({ path, directory })).uri;
const exists = (path) =>
  Filesystem.stat({ path })
    .then(() => true)
    .catch(() => false);
const errorOf = (error) => ({ code: error?.code ?? null, message: error?.message ?? String(error) });

async function timed(name, options) {
  const progress = [];
  const handle = await VideoTranscoder.addListener('progress', ({ progress: value }) => {
    progress.push(value);
    progressElement.textContent = `${name}: ${Math.round(value * 100)}%`;
  });
  const started = Date.now();
  try {
    const result = await VideoTranscoder.transcode(options);
    return { name, options, ok: true, result, wallMs: Date.now() - started, progress: summary(progress) };
  } catch (error) {
    return { name, options, ok: false, error: errorOf(error), wallMs: Date.now() - started, progress: summary(progress) };
  } finally {
    await handle.remove();
  }
}

function summary(values) {
  return {
    events: values.length,
    first: values[0] ?? null,
    last: values.at(-1) ?? null,
    monotonic: values.every((value, i) => i === 0 || value >= values[i - 1]),
  };
}

/** A content:// URI for a file in the app's external files directory, served by the app's own FileProvider (file_paths.xml). */
function contentUriOf(fileUri) {
  const root = 'file:///storage/emulated/0/';
  return fileUri.startsWith(root) ? `content://${appId}.fileprovider/my_images/${fileUri.slice(root.length)}` : null;
}

async function run() {
  logElement.textContent = '';
  let names;
  try {
    names = (await Filesystem.readdir({ path: 'in', directory })).files.map((file) => file.name).sort();
  } catch {
    log('no in/ folder: nothing to do');
    return;
  }
  const videos = names.filter((name) => /\.(mov|mp4|m4v|3gp)$/i.test(name));
  log(`${platform}: ${videos.length} videos in in/`);
  await Filesystem.rmdir({ path: 'out', directory, recursive: true }).catch(() => undefined);
  await Filesystem.mkdir({ path: 'out', directory, recursive: true });
  const out = await uriOf('out');
  const report = { platform, userAgent: navigator.userAgent, startedAt: new Date().toISOString(), cases: [] };
  const record = (entry) => {
    report.cases.push(entry);
    log(`${entry.name}: ${entry.ok ? `${entry.result.width}x${entry.result.height} ${entry.result.durationMs} ms ${entry.result.size} B` : `${entry.error.code} ${entry.error.message}`} (${entry.wallMs} ms, ${entry.progress.events} progress events)`);
  };

  // every input with the defaults
  for (const name of videos) {
    const base = name.replace(/\.[^.]+$/, '');
    record(await timed(name, { source: await uriOf(`in/${name}`), destination: `${out}/${base}.mp4` }));
  }

  const smallest = videos.find((name) => name.startsWith('hdr-hlg')) ?? videos[0];
  const largest = videos.find((name) => name.startsWith('iphone-hdr')) ?? videos.at(-1);
  if (smallest) {
    const source = await uriOf(`in/${smallest}`);
    // a plain path rather than a file:// URL, and the options all set
    record(
      await timed('options:path+maxSize+duration+bitrate', {
        source: source.replace('file://', ''),
        destination: `${out}/options.mp4`,
        maxSize: 128,
        maxDurationMs: 1000,
        videoBitrate: 300000,
      }),
    );
    // no destination: a new file in the cache or temporary directory
    const defaulted = await timed('default-destination', { source });
    defaulted.fileExisted = defaulted.ok ? await exists(defaulted.result.uri) : false;
    if (defaulted.ok) await Filesystem.deleteFile({ path: defaulted.result.uri }).catch(() => undefined);
    record(defaulted);
    // content:// read in place on Android; refused on iOS
    const content = platform === 'android' ? contentUriOf(source) : 'content://media/external/video/media/1';
    if (content) record(await timed('content-uri', { source: content, destination: `${out}/content.mp4` }));
  }

  if (largest) {
    // BUSY while one runs, then CANCELLED, and no file left
    const destination = `${out}/cancelled.mp4`;
    let cancelled = false;
    const handle = await VideoTranscoder.addListener('progress', ({ progress }) => {
      if (progress >= 0.1 && !cancelled) {
        cancelled = true;
        VideoTranscoder.cancel();
      }
    });
    const first = timed('cancel', { source: await uriOf(`in/${largest}`), destination });
    record(await timed('busy', { source: await uriOf(`in/${largest}`), destination: `${out}/busy.mp4` }));
    const result = await first;
    await handle.remove();
    result.fileLeft = await exists(destination);
    record(result);
  }

  await Filesystem.writeFile({ path: 'out/fake.mov', directory, data: 'not a video', encoding: Encoding.UTF8 });
  record(await timed('no-video', { source: await uriOf('out/fake.mov'), destination: `${out}/fake.mp4` }));
  await Filesystem.deleteFile({ path: 'out/fake.mov', directory });
  record(await timed('not-found', { source: `${out}/missing.mov` }));
  record(await timed('invalid:maxSize', { source: `${out}/missing.mov`, maxSize: 8 }));
  record(await timed('invalid:relative', { source: 'in/x.mov' }));

  report.finishedAt = new Date().toISOString();
  await Filesystem.writeFile({ path: 'out/results.json', directory, data: JSON.stringify(report, null, 2), encoding: Encoding.UTF8 });
  progressElement.textContent = 'done';
  log('DONE: out/results.json written');
}

document.getElementById('run').addEventListener('click', () => run().catch((error) => log(`FAILED ${error}`)));
run().catch((error) => log(`FAILED ${error}`));
