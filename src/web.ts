import { WebPlugin } from '@capacitor/core';

import type { TranscodeOptions, TranscodeResult, VideoTranscoderPlugin } from './definitions';

export class VideoTranscoderWeb extends WebPlugin implements VideoTranscoderPlugin {
  async transcode(options: TranscodeOptions): Promise<TranscodeResult> {
    throw this.unimplemented(`Cannot transcode ${options.source} on the web: it needs the platform's video encoder.`);
  }

  async cancel(): Promise<void> {
    throw this.unimplemented('cancel is not available on the web.');
  }
}
