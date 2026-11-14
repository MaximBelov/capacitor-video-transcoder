#!/usr/bin/env bash
# Writes the test videos in this folder with ffmpeg (built with libx264 and libx265). They are kept tiny on purpose: each one
# exists for one property the transcoder has to handle, not to look like a phone's recording.
#
#   rotated-pcm.mov   H.264 320x240 with a 90 degree display matrix, 2 s, PCM stereo at 16 kHz: rotation kept as metadata,
#                     audio that is not AAC encoded with the source's channel count, a sample rate AAC has
#   hdr-hlg.mov       HEVC Main 10, 256x144, BT.2020 HLG, 3 s, AAC mono: HDR tone-mapped to 8-bit BT.709, AAC copied
#   long-silent.mp4   H.264 640x360, 4 s, no audio: scaled down to maxSize, cut at maxDurationMs, no audio track made up
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i testsrc2=size=320x240:rate=30:duration=2 \
  -f lavfi -i "sine=frequency=440:sample_rate=16000:duration=2" \
  -filter_complex "[1:a]pan=stereo|c0=c0|c1=c0[a]" -map 0:v -map "[a]" \
  -c:v libx264 -profile:v main -pix_fmt yuv420p -crf 32 -c:a pcm_s16le "$tmp/rotated.mov"
# the rotation is a property of the input stream, so it is set while copying
ffmpeg -hide_banner -loglevel error -y -display_rotation:v:0 90 -i "$tmp/rotated.mov" -c copy rotated-pcm.mov

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i testsrc2=size=256x144:rate=30:duration=3 \
  -f lavfi -i "sine=frequency=880:sample_rate=44100:duration=3" -map 0:v -map 1:a \
  -vf format=yuv420p10le -c:v libx265 -tag:v hvc1 -profile:v main10 \
  -x265-params "log-level=error:crf=34:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc" \
  -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc \
  -c:a aac -ac 1 -b:a 48k hdr-hlg.mov

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i testsrc2=size=640x360:rate=30:duration=4 \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 34 -an long-silent.mp4
