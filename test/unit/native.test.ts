import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

import type { TranscodeResult, VideoTranscoderPlugin } from '../../src';

// What the native side of Capacitor injects into the web view: a bridge object that makes the platform 'android', the headers of
// the installed plugins, and nativePromise, which every promise method of a plugin goes through.
const result: TranscodeResult = {
  path: '/data/user/0/app/cache/video-transcoder/a.mp4',
  uri: 'file:///data/user/0/app/cache/video-transcoder/a.mp4',
  width: 720,
  height: 1280,
  durationMs: 30000,
  size: 6_800_000,
};
const nativePromise = vi.fn(async (_plugin: string, method: string): Promise<unknown> =>
  method === 'transcode' ? result : undefined,
);
const g = globalThis as Record<string, unknown>;

let VideoTranscoder: VideoTranscoderPlugin;

beforeAll(async () => {
  g.androidBridge = {};
  g.Capacitor = {
    PluginHeaders: [
      {
        name: 'VideoTranscoder',
        methods: [
          { name: 'transcode', rtype: 'promise' },
          { name: 'cancel', rtype: 'promise' },
        ],
      },
    ],
    nativePromise,
  };
  ({ VideoTranscoder } = await import('../../src'));
});

afterAll(() => {
  delete g.androidBridge;
  delete g.Capacitor;
});

describe('on a native platform', () => {
  it('sends transcode with its options, as they are, to the native plugin named VideoTranscoder', async () => {
    const options = {
      source: 'content://media/external/video/media/42',
      maxSize: 960,
      maxDurationMs: 15000,
      videoBitrate: 1_200_000,
    };
    await expect(VideoTranscoder.transcode(options)).resolves.toEqual(result);
    expect(nativePromise).toHaveBeenLastCalledWith('VideoTranscoder', 'transcode', options);
  });

  it('sends cancel', async () => {
    await VideoTranscoder.cancel();
    expect(nativePromise).toHaveBeenLastCalledWith('VideoTranscoder', 'cancel', undefined);
  });

  it('passes on the code the native side rejects with', async () => {
    nativePromise.mockRejectedValueOnce(
      Object.assign(new Error('another transcode is still running'), { code: 'BUSY' }),
    );
    await expect(VideoTranscoder.transcode({ source: '/in.mov' })).rejects.toMatchObject({ code: 'BUSY' });
  });
});
