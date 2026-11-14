# capacitor-video-transcoder

Turn a video from the phone's camera or gallery into an MP4 that every web browser plays, on iOS and Android, from a Capacitor app.

A phone records what suits the phone: HEVC, often 10-bit HDR, 4K, in a `.mov` on iOS. A browser on another computer may play none
of that. This plugin writes a small, plain MP4 instead, with the platform's own hardware encoder: AVFoundation on iOS, Media3
Transformer on Android. No FFmpeg, nothing to license, nothing large added to the app.

What comes out:

- H.264 video, High profile where the encoder offers it, 8-bit 4:2:0, tagged BT.709
- an HDR source (HLG or PQ) tone-mapped to SDR, so it does not look washed out
- AAC audio: an AAC track is copied as it is, anything else is encoded, keeping mono as mono and stereo as stereo
- the longer side at most `maxSize` (1280 by default), the aspect ratio kept, both sides even
- cut at `maxDurationMs` (30 seconds by default)
- `moov` before `mdat` ("faststart"), so playback starts before the whole file has downloaded
- a portrait video stored the way the phone stored it, with its rotation as track metadata, so players show it upright
- a video bitrate you choose (1.8 Mbit/s by default)

## Install

```bash
npm install capacitor-video-transcoder
npx cap sync
```

Requires Capacitor 8. Android 8.0 (API 26) or newer, iOS 15 or newer. On iOS the plugin is a Swift package; CocoaPods works too.
Android adds [Media3 Transformer](https://developer.android.com/media/media3/transformer); iOS uses system frameworks only.

## Use

```typescript
import { VideoTranscoder } from 'capacitor-video-transcoder';

const progress = await VideoTranscoder.addListener('progress', ({ progress }) => {
  console.log(`${Math.round(progress * 100)}%`);
});
try {
  const video = await VideoTranscoder.transcode({ source: picked.path });
  // video.path is an MP4 in the cache directory: upload it, then delete it
  console.log(video.width, video.height, video.durationMs, video.size);
} catch (error) {
  if ((error as { code?: string }).code !== 'CANCELLED') throw error;
} finally {
  await progress.remove();
}
```

`source` is an absolute path or a `file://` URL. On Android it can also be the `content://` URI a picker returns: the plugin
reads it in place, so there is no need to copy the video into the app first.

Stop a running transcode with `cancel()`. The `transcode` call then rejects with `CANCELLED`, and no file is left behind.

One transcode runs at a time. A second call while one is running rejects with `BUSY`.

### Replacing an FFmpeg command

The defaults match what this FFmpeg command does, which is a common way to make a phone video safe for a browser:

```
ffmpeg -i in.mov -vcodec libx264 -vf scale=w=1280:h=1280:force_original_aspect_ratio=decrease \
  -pix_fmt yuv420p -c:a aac -ss 00:00 -to 00:30 -movflags +faststart out.mp4
```

The differences: this plugin also tags the colour as BT.709 and tone-maps HDR (that command leaves HDR colour values in an SDR
file), keeps an AAC track as it is instead of re-encoding it, and asks the encoder for an average bitrate rather than a quality
level, so file sizes are predictable.

## How each platform does it

**iOS.** `AVAssetReader` decodes the video into 8-bit 4:2:0 frames converted to BT.709 (this is where HDR is tone-mapped), and
`AVAssetWriter` encodes them with the H.264 encoder at the size and bitrate asked for, writing the source track's transform as the
output track's transform. An AAC audio track is passed through; any other is decoded and encoded to AAC with the source's channel
count (more than two channels are mixed down to stereo) and sample rate. `shouldOptimizeForNetworkUse` puts the `moov` box first.

**Android.** Media3 `Transformer` with H.264 and AAC as the output formats, a `Presentation` effect that scales to fit, a clipping
configuration for the length, `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` for HDR, and Media3's own MP4 muxer with streamable
output for the `moov` box. Transformer copies an AAC track without decoding it, and picks H.264 High when the encoder has it. HDR
tone-mapping needs Android 10 (API 29) or newer; an HDR video on an older phone is rare, and fails with `FAILED`.

<docgen-index>

* [`transcode(...)`](#transcode)
* [`cancel()`](#cancel)
* [`addListener('progress', ...)`](#addlistenerprogress-)
* [`removeAllListeners()`](#removealllisteners)
* [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### transcode(...)

```typescript
transcode(options: TranscodeOptions) => Promise<TranscodeResult>
```

Transcode a video into an MP4 that web browsers play:

- H.264 video (High profile where the encoder offers it), 8-bit 4:2:0, tagged
  BT.709; an HDR source (HLG or PQ) is tone-mapped to SDR
- AAC audio: an AAC source track is copied as it is, anything else is
  encoded; a video without sound gets no audio track
- the longer side at most `maxSize`, cut at `maxDurationMs`
- the index (`moov`) before the media data, so playback can start before
  the whole file has downloaded
- a portrait video keeps its rotation as track metadata, the way a phone
  records it, so players show it upright

One runs at a time: a second call while one is running rejects with `BUSY`.
On the web it rejects with the `UNIMPLEMENTED` code.

| Param         | Type                                                          |
| ------------- | ------------------------------------------------------------- |
| **`options`** | <code><a href="#transcodeoptions">TranscodeOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#transcoderesult">TranscodeResult</a>&gt;</code>

--------------------


### cancel()

```typescript
cancel() => Promise<void>
```

Stop the running `transcode`, which then rejects with `CANCELLED` and leaves
no file behind. Resolves straight away, and does nothing when none is
running. On the web it rejects with the `UNIMPLEMENTED` code.

--------------------


### addListener('progress', ...)

```typescript
addListener(eventName: 'progress', listenerFunc: (event: TranscodeProgress) => void) => Promise<PluginListenerHandle>
```

Listen to the progress of the running `transcode`.

| Param              | Type                                                                                |
| ------------------ | ----------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'progress'</code>                                                             |
| **`listenerFunc`** | <code>(event: <a href="#transcodeprogress">TranscodeProgress</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### removeAllListeners()

```typescript
removeAllListeners() => Promise<void>
```

Remove every listener of this plugin.

--------------------


### Interfaces


#### TranscodeResult

| Prop             | Type                | Description                                                                                                           |
| ---------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------- |
| **`path`**       | <code>string</code> | The absolute path of the MP4 that was written.                                                                        |
| **`uri`**        | <code>string</code> | The same file as a `file://` URL.                                                                                     |
| **`width`**      | <code>number</code> | The width of the video as a player shows it, upright: the rotation the output carries as metadata is already applied. |
| **`height`**     | <code>number</code> | The height of the video as a player shows it, upright.                                                                |
| **`durationMs`** | <code>number</code> | The length of the output, in milliseconds.                                                                            |
| **`size`**       | <code>number</code> | The size of the output file, in bytes.                                                                                |


#### TranscodeOptions

| Prop                | Type                | Description                                                                                                                                                                                                                                                                                                                | Default              |
| ------------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- |
| **`source`**        | <code>string</code> | The video to transcode: an absolute path or a `file://` URL. On Android it can also be a `content://` URI, such as the one a system picker returns; it is read in place, without a copy.                                                                                                                                   |                      |
| **`destination`**   | <code>string</code> | Where to write the MP4: an absolute path or a `file://` URL. A file that is already there is replaced, and missing directories are created. When it is left out, a new file is created in the app's cache directory (Android) or temporary directory (iOS). The app owns that file and deletes it when it is done with it. |                      |
| **`maxSize`**       | <code>number</code> | The longest side of the output, in pixels. A larger video is scaled down to fit, keeping its aspect ratio; a smaller one keeps its size. Both sides are rounded down to an even number, as H.264 4:2:0 needs. A whole number, at least 16.                                                                                 | <code>1280</code>    |
| **`maxDurationMs`** | <code>number</code> | The longest the output may be, in milliseconds. A longer video is cut at this point; a shorter one is kept whole. A whole number, at least 1.                                                                                                                                                                              | <code>30000</code>   |
| **`videoBitrate`**  | <code>number</code> | The average video bitrate the encoder is asked for, in bits per second. A whole number, at least 1.                                                                                                                                                                                                                        | <code>1800000</code> |


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |


#### TranscodeProgress

| Prop           | Type                | Description                                                                                                          |
| -------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------- |
| **`progress`** | <code>number</code> | How far the running `transcode` is, from 0 to 1. It only grows, and the last event before the promise resolves is 1. |

</docgen-api>

## Checked on phones

The example app run on a Pixel 10a (Android 16) and an iPhone 16 (iOS 27), on three phone recordings and the three test clips, with
every output read back with `ffprobe`: H.264 High, `yuv420p`, BT.709 primaries, transfer and matrix, AAC LC, `moov` before `mdat`,
the rotation of the source kept, and the size, length and bitrate asked for.

| Source | Android output | iOS output |
| --- | --- | --- |
| iPhone HEVC 10-bit HLG, 1920x1080 rotated, 35 s, AAC stereo | 1280x720 rotated (720x1280 shown), 30.0 s, 7.7 MB, 3.5 s | 1280x720 rotated, 30.0 s, 7.2 MB, 2.8 s |
| Android HEVC, 1920x1080 rotated, 12 s, AAC stereo | 1280x720 rotated, 12.0 s, 3.3 MB, 1.7 s | 1280x720 rotated, 12.0 s, 2.9 MB, 1.1 s |
| H.264 1920x1080, 10 s, AAC mono | 1280x720, 10.0 s, 2.7 MB, 1.5 s | 1280x720, 10.0 s, 2.3 MB, 0.9 s |
| PCM stereo 16 kHz (test clip) | AAC stereo 16 kHz | AAC stereo 16 kHz |
| no audio (test clip) | no audio track | no audio track |

Times are the whole call, as JavaScript saw it. Cancelling, `BUSY`, a `content://` URI on Android, the default destination and the
error codes were checked in the same runs.

## Tests

| What | Where it runs | Command |
| --- | --- | --- |
| The TypeScript: the bridge calls, the web fallback, and that the API, both platforms and this README agree | Node | `npm test` |
| The option parsing and size arithmetic of the Kotlin | JVM (no device) | `npm run test:android` |
| The Swift core: option parsing, size arithmetic, and end-to-end transcodes of the clips in `test/fixtures` read back with AVFoundation | a Mac, `swift test` (no simulator) | `npm run test:core` |
| The same Swift tests and the bridge's own tests | an iOS simulator | `npm run test:ios` |
| The example app, built with the plugin installed | Gradle, Xcode | `npm run example:android:build`, `npm run example:ios:build` |

`test/fixtures/make-fixtures.sh` writes the test clips with FFmpeg. The example app in `example-app/` transcodes every video it finds
in its `in/` folder when it starts, and writes the results to `out/`: it is how the plugin is checked on a phone.

## License

MIT
