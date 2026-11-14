import { CapacitorException, ExceptionCode } from '@capacitor/core';
import { describe, expect, it } from 'vitest';

import { VideoTranscoder } from '../../src';
import { VideoTranscoderWeb } from '../../src/web';

// No native bridge on globalThis, so Capacitor reports the platform as 'web' and loads src/web.ts.
describe('on the web', () => {
  it('rejects transcode with UNIMPLEMENTED, naming the source', async () => {
    await expect(VideoTranscoder.transcode({ source: '/in.mov' })).rejects.toMatchObject({
      code: ExceptionCode.Unimplemented,
      message: "Cannot transcode /in.mov on the web: it needs the platform's video encoder.",
    });
  });

  it('rejects cancel with UNIMPLEMENTED', async () => {
    await expect(VideoTranscoder.cancel()).rejects.toMatchObject({ code: ExceptionCode.Unimplemented });
  });

  it('rejects with a CapacitorException, not a plain Error', async () => {
    const error = await new VideoTranscoderWeb().transcode({ source: '/in.mov' }).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(CapacitorException);
  });

  it('takes a progress listener and lets it go', async () => {
    const handle = await VideoTranscoder.addListener('progress', () => undefined);
    await handle.remove();
    await VideoTranscoder.removeAllListeners();
  });
});
