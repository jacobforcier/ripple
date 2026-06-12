#!/bin/bash
# Assemble Reel 002 from frames + the composed audio bed.
set -euo pipefail
cd "$(dirname "$0")/.."
ffmpeg -y \
  -framerate 30 -i "marketing/output/reel002_frames/%04d.png" \
  -i "marketing/output/reel002_audio.wav" \
  -map 0:v -map 1:a \
  -c:v libx264 -crf 18 -pix_fmt yuv420p -r 30 \
  -c:a aac -b:a 128k -ar 44100 \
  -t 16 -movflags +faststart \
  "marketing/output/reel002_v1.mp4"
ffprobe -v error -show_entries format=duration,size -of default=noprint_wrappers=1 "marketing/output/reel002_v1.mp4"
echo "✓ marketing/output/reel002_v1.mp4"
