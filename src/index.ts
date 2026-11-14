import { registerPlugin } from '@capacitor/core';

import type { VideoTranscoderPlugin } from './definitions';

const VideoTranscoder = registerPlugin<VideoTranscoderPlugin>('VideoTranscoder', {
  web: () => import('./web').then((m) => new m.VideoTranscoderWeb()),
});

export * from './definitions';
export { VideoTranscoder };
