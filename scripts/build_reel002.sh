#!/bin/bash
# Composite the Ripple overlay over the Veo water hero shot.
#   bg  = marketing/raw/veo_water.mp4 (8s, real audio) → freeze last frame to 12s
#   fg  = marketing/output/reel002_overlay/%04d.png (transparent, 12s @30fps)
#   aud = Veo's real water audio (faded) + soft end chord at the reveal
set -euo pipefail
cd "$(dirname "$0")/.."

RAW="marketing/raw/veo_water.mp4"
OVL="marketing/output/reel002_overlay/%04d.png"
CHORD="marketing/output/reel002_endchord.wav"
OUT="marketing/output/reel002_v1.mp4"

ffmpeg -y \
  -i "$RAW" \
  -framerate 30 -i "$OVL" \
  -i "$CHORD" \
  -filter_complex "
    [0:v]tpad=stop_mode=clone:stop_duration=4,fps=30,format=rgba[bg];
    [bg][1:v]overlay=0:0:format=auto,format=yuv420p,trim=0:12,setpts=PTS-STARTPTS[v];
    [0:a]afade=t=out:st=7.6:d=0.4,apad=whole_dur=12[wa];
    [2:a]adelay=8200|8200[ca];
    [wa][ca]amix=inputs=2:duration=longest:normalize=0,volume=1.4[a]
  " \
  -map "[v]" -map "[a]" \
  -c:v libx264 -crf 18 -pix_fmt yuv420p -r 30 \
  -c:a aac -b:a 160k -ar 44100 \
  -t 12 -movflags +faststart \
  "$OUT"

ffprobe -v error -show_entries format=duration,size -of default=noprint_wrappers=1 "$OUT"
echo "✓ $OUT"
