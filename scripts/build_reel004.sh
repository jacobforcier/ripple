#!/bin/bash
# Reel 004 — mux the rendered receipt frames with the real printer sound.
# Timeline: print1 0.5–6.0s · tear ~7.3s · print2 8.2–10.6s · end 13.6s.
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMES="marketing/output/reel004_frames/%04d.png"
SND="marketing/sfx/printer.mp3"
OUT="marketing/output/reel004_v1.mp4"

ffmpeg -y \
  -framerate 30 -i "$FRAMES" \
  -i "$SND" \
  -filter_complex "
    [1:a]asplit=3[a1][a2][a3];
    [a1]atrim=0:5.5,asetpts=PTS-STARTPTS,afade=t=out:st=5.3:d=0.2,adelay=500|500[s1];
    [a2]atrim=10.7:11.5,asetpts=PTS-STARTPTS,adelay=7250|7250,volume=1.3[tr];
    [a3]atrim=0:2.4,asetpts=PTS-STARTPTS,afade=t=out:st=2.2:d=0.2,adelay=8200|8200[s2];
    [s1][tr][s2]amix=inputs=3:duration=longest:normalize=0,volume=1.5,
      afade=t=out:st=13.1:d=0.5[a]
  " \
  -map 0:v -map "[a]" \
  -c:v libx264 -crf 18 -pix_fmt yuv420p -r 30 \
  -c:a aac -b:a 160k -ar 44100 \
  -t 13.6 -movflags +faststart \
  "$OUT"

ffprobe -v error -show_entries format=duration,size -of default=noprint_wrappers=1 "$OUT"
echo "✓ $OUT"
