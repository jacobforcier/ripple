#!/bin/bash
# Assemble Reel 001 from rendered frames + SFX.
# Run after: python3 scripts/generate_reel001.py
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMES="marketing/output/reel001_frames"
SFX="marketing/sfx"
OUT="marketing/output/reel001_v1.mp4"

# SFX timeline (ms): pop=ask, whoosh=send, pop=typing, ding=SOLD,
# 3 quiet pops=ledger ticks, thud=$0.00, ding=$1.80 flip, pop=loop bubble
ffmpeg -y \
  -framerate 30 -i "$FRAMES/%04d.png" \
  -i "$SFX/pop.wav"    \
  -i "$SFX/whoosh.wav" \
  -i "$SFX/pop.wav"    \
  -i "$SFX/ding.wav"   \
  -i "$SFX/pop.wav"    \
  -i "$SFX/pop.wav"    \
  -i "$SFX/pop.wav"    \
  -i "$SFX/thud.wav"   \
  -i "$SFX/ding.wav"   \
  -i "$SFX/pop.wav"    \
  -filter_complex "\
    [1:a]adelay=300:all=1,volume=0.9[a1]; \
    [2:a]adelay=1600:all=1,volume=0.7[a2]; \
    [3:a]adelay=2000:all=1,volume=0.4[a3]; \
    [4:a]adelay=2780:all=1,volume=0.9[a4]; \
    [5:a]adelay=6400:all=1,volume=0.35[a5]; \
    [6:a]adelay=7200:all=1,volume=0.35[a6]; \
    [7:a]adelay=8000:all=1,volume=0.35[a7]; \
    [8:a]adelay=8900:all=1,volume=1.0[a8]; \
    [9:a]adelay=10300:all=1,volume=0.9[a9]; \
    [10:a]adelay=13300:all=1,volume=0.9[a10]; \
    [a1][a2][a3][a4][a5][a6][a7][a8][a9][a10]amix=inputs=10:normalize=0,apad[aout]" \
  -map 0:v -map "[aout]" \
  -c:v libx264 -crf 18 -pix_fmt yuv420p -r 30 \
  -c:a aac -b:a 128k -ar 44100 \
  -t 14 -movflags +faststart \
  "$OUT"

echo
ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 "$OUT"
echo "✓ $OUT"
