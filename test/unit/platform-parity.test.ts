import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

// The methods of definitions.ts, the native methods of each platform, the error codes and the README have to agree: a method
// that one platform lacks rejects there with "not implemented", which no unit test on the other platform would notice.
const root = join(__dirname, '..', '..');
const read = (file: string) => readFileSync(join(root, file), 'utf8');

const ios = 'ios/Sources/VideoTranscoderPlugin/VideoTranscoderPlugin.swift';
const iosCore = 'ios/Sources/VideoTranscoderCore/TranscodeOptions.swift';
const android = 'android/src/main/kotlin/io/github/maximbelov/videotranscoder/VideoTranscoderPlugin.kt';
const androidCore = 'android/src/main/kotlin/io/github/maximbelov/videotranscoder/TranscodeOptions.kt';
const listenerMethods = new Set(['addListener', 'removeAllListeners']);

function declared(): string[] {
  const body = /export interface VideoTranscoderPlugin \{([\s\S]*?)\n\}/.exec(read('src/definitions.ts'))?.[1] ?? '';
  return [...body.matchAll(/^\s{2}(\w+)\(/gm)].map((m) => m[1]).filter((name) => !listenerMethods.has(name));
}

describe('platform parity', () => {
  const methods = declared();

  it('finds the methods', () => {
    expect(methods).toEqual(['transcode', 'cancel']);
  });

  it('iOS registers exactly the methods of the API, each with its @objc function', () => {
    const source = read(ios);
    expect([...source.matchAll(/CAPPluginMethod\(name: "(\w+)"/g)].map((m) => m[1])).toEqual(methods);
    expect([...source.matchAll(/@objc func (\w+)\(_ call: CAPPluginCall\)/g)].map((m) => m[1])).toEqual(methods);
  });

  it('Android annotates exactly the methods of the API', () => {
    expect([...read(android).matchAll(/@PluginMethod\s+fun (\w+)\(/g)].map((m) => m[1])).toEqual(methods);
  });

  it('the plugin has the same name in JavaScript, Swift and Kotlin', () => {
    expect(read('src/index.ts')).toContain("registerPlugin<VideoTranscoderPlugin>('VideoTranscoder'");
    expect(read(ios)).toContain('jsName = "VideoTranscoder"');
    expect(read(android)).toContain('@CapacitorPlugin(name = "VideoTranscoder")');
  });

  it('the progress event has the same name and field on both platforms', () => {
    expect(read('src/definitions.ts')).toMatch(/addListener\(eventName: 'progress'/);
    expect(read(ios)).toContain('notifyListeners("progress", data: ["progress": progress])');
    expect(read(android)).toContain('notifyListeners("progress", JSObject().put("progress", progress))');
  });

  it('the result has the same fields everywhere', () => {
    const body = /export interface TranscodeResult \{([\s\S]*?)\n\}/.exec(read('src/definitions.ts'))?.[1] ?? '';
    const fields = [...body.matchAll(/^\s{2}(\w+):/gm)].map((m) => m[1]).sort();
    expect(fields).toEqual(['durationMs', 'height', 'path', 'size', 'uri', 'width']);
    for (const field of fields) {
      expect(read(ios), `iOS returns ${field}`).toContain(`"${field}":`);
      expect(read(android), `Android returns ${field}`).toContain(`.put("${field}",`);
    }
  });

  it('the options are read under the same names everywhere', () => {
    const body = /export interface TranscodeOptions \{([\s\S]*?)\n\}/.exec(read('src/definitions.ts'))?.[1] ?? '';
    const options = [...body.matchAll(/^\s{2}(\w+)\??:/gm)].map((m) => m[1]);
    expect(options).toEqual(['source', 'destination', 'maxSize', 'maxDurationMs', 'videoBitrate']);
    for (const option of options) {
      expect(read(iosCore), `iOS reads ${option}`).toContain(`raw["${option}"]`);
      expect(read(androidCore), `Android reads ${option}`).toContain(`get("${option}")`);
    }
  });

  it('the defaults are the same everywhere', () => {
    const definitions = read('src/definitions.ts');
    for (const [name, value] of [
      ['maxSize', '1280'],
      ['maxDurationMs', '30000'],
      ['videoBitrate', '1800000'],
    ]) {
      expect(definitions).toMatch(new RegExp(`@default ${value}\\n\\s+\\*/\\n\\s+${name}\\?`));
    }
    const ios = read(iosCore).replace(/_/g, '');
    const kotlin = read(androidCore).replace(/_/g, '');
    for (const line of [
      'defaultMaxSize = 1280',
      'defaultMaxDurationMs = 30000',
      'defaultVideoBitrate = 1800000',
      'minimumMaxSize = 16',
    ]) {
      expect(ios).toContain(line);
    }
    for (const line of [
      'DEFAULTMAXSIZE = 1280',
      'DEFAULTMAXDURATIONMS = 30000L',
      'DEFAULTVIDEOBITRATE = 1800000',
      'MINIMUMMAXSIZE = 16',
    ]) {
      expect(kotlin).toContain(line);
    }
  });

  it('the error codes are the same on every platform', () => {
    const codes = /export type TranscodeErrorCode =([^;]*);/.exec(read('src/definitions.ts'))?.[1] ?? '';
    const ts = [...codes.matchAll(/'([A-Z_]+)'/g)].map((m) => m[1]).sort();
    const swift = [...read(iosCore).matchAll(/case \w+ = "([A-Z_]+)"/g)].map((m) => m[1]).sort();
    const kotlin = (/enum class ErrorCode \{([^}]*)\}/.exec(read(androidCore))?.[1] ?? '')
      .split(',')
      .map((code) => code.trim())
      .sort();
    expect(ts).toEqual(['BUSY', 'CANCELLED', 'FAILED', 'INVALID_ARGUMENT', 'NOT_FOUND', 'NO_VIDEO']);
    expect(swift).toEqual(ts);
    expect(kotlin).toEqual(ts);
  });

  it.each(methods)('%s is in the README', (method) => {
    expect(read('README.md')).toContain(`### ${method}(`);
  });
});
