import { WebPlugin } from '@capacitor/core';

import type { VideoTranscoderPlugin } from './definitions';

export class VideoTranscoderWeb extends WebPlugin implements VideoTranscoderPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
