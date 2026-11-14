import type { PluginListenerHandle } from '@capacitor/core';

export interface TranscodeOptions {
  /**
   * The video to transcode: an absolute path or a `file://` URL. On Android it
   * can also be a `content://` URI, such as the one a system picker returns; it
   * is read in place, without a copy.
   */
  source: string;
  /**
   * Where to write the MP4: an absolute path or a `file://` URL. A file that is
   * already there is replaced, and missing directories are created.
   *
   * When it is left out, a new file is created in the app's cache directory
   * (Android) or temporary directory (iOS). The app owns that file and deletes it
   * when it is done with it.
   */
  destination?: string;
  /**
   * The longest side of the output, in pixels. A larger video is scaled down to
   * fit, keeping its aspect ratio; a smaller one keeps its size. Both sides are
   * rounded down to an even number, as H.264 4:2:0 needs. A whole number, at
   * least 16.
   *
   * @default 1280
   */
  maxSize?: number;
  /**
   * The longest the output may be, in milliseconds. A longer video is cut at
   * this point; a shorter one is kept whole. A whole number, at least 1.
   *
   * @default 30000
   */
  maxDurationMs?: number;
  /**
   * The average video bitrate the encoder is asked for, in bits per second.
   * A whole number, at least 1.
   *
   * @default 1800000
   */
  videoBitrate?: number;
}

export interface TranscodeResult {
  /**
   * The absolute path of the MP4 that was written.
   */
  path: string;
  /**
   * The same file as a `file://` URL.
   */
  uri: string;
  /**
   * The width of the video as a player shows it, upright: the rotation the
   * output carries as metadata is already applied.
   */
  width: number;
  /**
   * The height of the video as a player shows it, upright.
   */
  height: number;
  /**
   * The length of the output, in milliseconds.
   */
  durationMs: number;
  /**
   * The size of the output file, in bytes.
   */
  size: number;
}

export interface TranscodeProgress {
  /**
   * How far the running `transcode` is, from 0 to 1. It only grows, and the
   * last event before the promise resolves is 1.
   */
  progress: number;
}

/**
 * Why a call failed, as the `code` of the rejected error.
 *
 * - `INVALID_ARGUMENT`: `source` is missing or not a path or URL this platform reads, `destination` is not a path or
 *   `file://` URL, or a number is out of range or not a whole number
 * - `NOT_FOUND`: there is no file at `source`, or it cannot be opened
 * - `NO_VIDEO`: `source` is not a video this device reads, or has no video track
 * - `BUSY`: another `transcode` is still running; one runs at a time
 * - `CANCELLED`: `cancel()` stopped it; nothing is left at the destination
 * - `FAILED`: the decoder, the encoder or the writer failed; nothing is left at the destination
 */
export type TranscodeErrorCode = 'INVALID_ARGUMENT' | 'NOT_FOUND' | 'NO_VIDEO' | 'BUSY' | 'CANCELLED' | 'FAILED';

export interface VideoTranscoderPlugin {
  /**
   * Transcode a video into an MP4 that web browsers play:
   *
   * - H.264 video (High profile where the encoder offers it), 8-bit 4:2:0, tagged
   *   BT.709; an HDR source (HLG or PQ) is tone-mapped to SDR
   * - AAC audio: an AAC source track is copied as it is, anything else is
   *   encoded; a video without sound gets no audio track
   * - the longer side at most `maxSize`, cut at `maxDurationMs`
   * - the index (`moov`) before the media data, so playback can start before
   *   the whole file has downloaded
   * - a portrait video keeps its rotation as track metadata, the way a phone
   *   records it, so players show it upright
   *
   * One runs at a time: a second call while one is running rejects with `BUSY`.
   * On the web it rejects with the `UNIMPLEMENTED` code.
   */
  transcode(options: TranscodeOptions): Promise<TranscodeResult>;

  /**
   * Stop the running `transcode`, which then rejects with `CANCELLED` and leaves
   * no file behind. Resolves straight away, and does nothing when none is
   * running. On the web it rejects with the `UNIMPLEMENTED` code.
   */
  cancel(): Promise<void>;

  /**
   * Listen to the progress of the running `transcode`.
   */
  addListener(eventName: 'progress', listenerFunc: (event: TranscodeProgress) => void): Promise<PluginListenerHandle>;

  /**
   * Remove every listener of this plugin.
   */
  removeAllListeners(): Promise<void>;
}
