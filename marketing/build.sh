#!/usr/bin/env bash
#
# build.sh — assemble the Ripple short-form video, kinetic version.
#
# Pipeline:
#   1. Each title card → short MP4 with Ken Burns motion baked in
#   2. $40 reveal → pre-rendered counter MP4 (rolls 0→40 with color pulse)
#   3. All slots concat'd into a video track
#   4. VO + ducked BGM mixed under
#   5. Whisper-timed captions burned in via libass
#
# Modes:
#   ./build.sh placeholder  — all card-only slots (no iPhone clips needed)
#   ./build.sh final         — substitutes clip1/2/3 from raw/ into the demo slot
#
# Output: marketing/output/ripple_<mode>.mp4 (1080×1920, H.264, AAC)

set -euo pipefail

MODE="${1:-placeholder}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CARDS="$HERE/cards"
RAW="$HERE/raw"
AUDIO="$HERE/audio/vo_v3.mp3"   # vo_v2 + 0.5s silence inserted at the "$0" beat
BGM="$HERE/audio/bgm.mp3"
CAPTIONS="$HERE/captions.ass"
FONTSDIR="$HERE/../scripts/fonts"
SFX_DIR="$HERE/sfx"
OUT_DIR="$HERE/output"
TMP_DIR="$OUT_DIR/.tmp_${MODE}"
OUT="$OUT_DIR/ripple_${MODE}.mp4"

BGM_DB="-18"
FADEOUT="1.0"

# SFX trigger times in the master timeline (seconds)
SFX_POP_AT="0.05"      # pop.wav  — bubble appears
SFX_WHOOSH_AT="1.45"   # whoosh.wav — transition off hook segment (currently unused)
SFX_DING_AT="19.80"    # ding.wav — $40 lands (slot_total start 18.80 + 1.0s roll)
# Cha-ching plays as each earned-stamp slams down (slot_start + 1.8s)
SFX_CHACHING_1_AT="5.90"   # Flip 7 stamp
SFX_CHACHING_2_AT="11.60"  # Air fryer stamp
SFX_CHACHING_3_AT="15.70"  # Owala stamp

mkdir -p "$OUT_DIR" "$TMP_DIR"

[[ -f "$AUDIO"    ]] || { echo "✗ Missing VO at $AUDIO" >&2; exit 1; }
[[ -f "$CAPTIONS" ]] || { echo "✗ Missing captions at $CAPTIONS" >&2; exit 1; }
for c in 01_hook 02_flip7 03_airfryer 04_owala 05b_hero 06_outro; do
  [[ -f "$CARDS/$c.png" ]] || { echo "✗ Missing card: $c.png" >&2; exit 1; }
done
[[ -f "$CARDS/05_total_counter.mp4" ]] || \
  { echo "✗ Missing counter video — run scripts/generate_counter.py" >&2; exit 1; }
[[ -f "$CARDS/00_hook_imessage.mp4" ]] || \
  { echo "✗ Missing iMessage hook — run scripts/generate_hook.py" >&2; exit 1; }
for s in pop whoosh ding chaching; do
  [[ -f "$SFX_DIR/$s.wav" ]] || \
    { echo "✗ Missing $SFX_DIR/$s.wav — run scripts/generate_sfx.py" >&2; exit 1; }
done

# ── Timing (from silence analysis of vo_v2.mp3, total 38.03s) ────────────────
# Hook slot is split into two pieces: 1.6s of iMessage bubble + 2.5s of the
# original title card. Audio still starts at t=0 (VO says "Stuff my friends
# bought…" under the bubble) so no preroll offset is needed.
slot_hook_bubble=1.60
slot_hook_card=2.50
slot_flip7=5.70
slot_airfryer=4.10
slot_owala=4.90
slot_total=6.05          # 5.55 + 0.5s held-$0 emphasis (silence inserted in VO)
slot_hero=1.45           # "ripple" wordmark slam for "that's why I built Ripple"
slot_demo=8.95
slot_outro=3.33

# BGM duck window — kills music for the $0 emphasis beat, swells back in
# right when the hero wordmark lands.
BGM_DUCK_OUT="23.00"     # master t — start fading BGM out (drop is starting)
BGM_DUCK_OUT_DUR="0.30"
BGM_DUCK_IN="24.85"      # master t — start swelling BGM back (hero appears, +0.5s)
BGM_DUCK_IN_DUR="0.40"

# When BGM swells back in, jump the playhead this far into the track (seconds
# from the start of bgm.mp3). The Nova Notes intro is too gentle for the
# post-$0 comeback moment — skip past it into the loud melody section.
BGM_PEAK_OFFSET="4.0"

FPS=30

# ── Per-slot renderers ──────────────────────────────────────────────────────
# Each emits a normalized 1080×1920 H.264 MP4 (no audio) into $TMP_DIR.

render_product_slot() {
  # Card with Ken Burns + earned-stamp slam overlay.
  # Args: card.png  stamp.png  duration  out.mp4  zoom_dir
  local card="$1" stamp="$2" dur="$3" out="$4" mode="${5:-pan-right}"
  local total_frames
  total_frames=$(awk "BEGIN { printf \"%d\", $dur * $FPS }")

  # Stamp lands 1.8s into the slot, holds for the rest.
  local SLAM_START="1.80"
  local SLAM_DUR="0.18"   # how long the slam animation runs
  local SLAM_END
  SLAM_END=$(awk "BEGIN { printf \"%.3f\", $SLAM_START + $SLAM_DUR }")

  local zoom_expr x_expr y_expr
  case "$mode" in
    pan-left)
      zoom_expr="1.06"
      x_expr="(iw-iw/zoom)*(1-on/${total_frames})"
      y_expr="ih/2-(ih/zoom/2)"
      ;;
    *)  # default pan-right
      zoom_expr="1.06"
      x_expr="(iw-iw/zoom)*(on/${total_frames})"
      y_expr="ih/2-(ih/zoom/2)"
      ;;
  esac

  # Stamp PNG is `-loop 1 -t DUR` so it becomes a video stream — animations
  # need multiple frames. We use fade=alpha=1 (which does support time exprs)
  # for the opacity ramp, and scale=eval=frame for the slam-in size bounce.
  ffmpeg -y -loglevel error \
    -i "$card" \
    -loop 1 -t "$dur" -i "$stamp" \
    -filter_complex "\
[0:v]zoompan=z='${zoom_expr}':x='${x_expr}':y='${y_expr}':d=${total_frames}:s=1080x1920:fps=${FPS},setsar=1[card];\
[1:v]format=rgba,fps=${FPS},\
scale=w='if(lt(t,${SLAM_START}),iw,if(lt(t,${SLAM_END}),iw*(1.5-0.5*(t-${SLAM_START})/${SLAM_DUR}),iw))':h=-1:eval=frame,\
fade=t=in:st=${SLAM_START}:d=${SLAM_DUR}:alpha=1[stamp];\
[card][stamp]overlay=x='(W-w)/2':y='H*0.68-h/2':enable='gte(t,${SLAM_START})',format=yuv420p[v]" \
    -map "[v]" \
    -c:v libx264 -preset ultrafast -crf 22 -r "$FPS" -an \
    "$out"
}

render_card_kenburns() {
  # Args: input.png  duration  out.mp4  zoom_dir(in|out|pan-left|pan-right)
  local src="$1" dur="$2" out="$3" mode="${4:-in}"
  local total_frames
  total_frames=$(awk "BEGIN { printf \"%d\", $dur * $FPS }")

  # Ken Burns parameters — gentle, ~8% over the slot
  local zoom_expr x_expr y_expr
  case "$mode" in
    in)
      zoom_expr="1.0+0.08*on/${total_frames}"
      x_expr="iw/2-(iw/zoom/2)"
      y_expr="ih/2-(ih/zoom/2)"
      ;;
    out)
      zoom_expr="1.08-0.08*on/${total_frames}"
      x_expr="iw/2-(iw/zoom/2)"
      y_expr="ih/2-(ih/zoom/2)"
      ;;
    pan-left)
      zoom_expr="1.06"
      x_expr="(iw-iw/zoom)*(1-on/${total_frames})"
      y_expr="ih/2-(ih/zoom/2)"
      ;;
    pan-right)
      zoom_expr="1.06"
      x_expr="(iw-iw/zoom)*(on/${total_frames})"
      y_expr="ih/2-(ih/zoom/2)"
      ;;
  esac

  # Single input frame → zoompan emits total_frames at 30fps. Using -loop 1
  # would feed multiple input frames, and zoompan's `d` is PER INPUT frame,
  # so the output explodes to (input_frames × d) frames.
  ffmpeg -y -loglevel error \
    -i "$src" \
    -vf "zoompan=z='${zoom_expr}':x='${x_expr}':y='${y_expr}':d=${total_frames}:s=1080x1920:fps=${FPS},setsar=1" \
    -frames:v "$total_frames" \
    -c:v libx264 -preset ultrafast -crf 22 -pix_fmt yuv420p \
    -r "$FPS" -an \
    "$out"
}

normalize_clip() {
  # iPhone clip → normalized 1080×1920 mp4 trimmed to duration
  local src="$1" dur="$2" out="$3"
  ffmpeg -y -loglevel error -i "$src" -t "$dur" \
    -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1,fps=${FPS}" \
    -c:v libx264 -preset medium -crf 19 -pix_fmt yuv420p \
    -r "$FPS" -an \
    "$out"
}

trim_counter() {
  # The pre-rendered counter is already 5.5s @ 30fps. Just normalize/strip audio.
  local src="$1" dur="$2" out="$3"
  ffmpeg -y -loglevel error -i "$src" -t "$dur" \
    -vf "scale=1080:1920,setsar=1,fps=${FPS}" \
    -c:v libx264 -preset medium -crf 19 -pix_fmt yuv420p \
    -r "$FPS" -an \
    "$out"
}

# ── Render every slot ───────────────────────────────────────────────────────
echo "→ Rendering slots..."
# Slot 0 — iMessage bubble pre-roll. Already rendered by generate_hook.py;
# just normalize timing/format.
ffmpeg -y -loglevel error -i "$CARDS/00_hook_imessage.mp4" -t "$slot_hook_bubble" \
  -vf "scale=1080:1920,setsar=1,fps=${FPS}" \
  -c:v libx264 -preset ultrafast -crf 22 -pix_fmt yuv420p -r "$FPS" -an \
  "$TMP_DIR/s00.mp4"
render_card_kenburns "$CARDS/01_hook.png"     "$slot_hook_card" "$TMP_DIR/s01.mp4"  in
render_product_slot  "$CARDS/02_flip7.png"    "$CARDS/stamp_5.png"  "$slot_flip7"    "$TMP_DIR/s02.mp4" pan-right
render_product_slot  "$CARDS/03_airfryer.png" "$CARDS/stamp_25.png" "$slot_airfryer" "$TMP_DIR/s03.mp4" pan-left
render_product_slot  "$CARDS/04_owala.png"    "$CARDS/stamp_10.png" "$slot_owala"    "$TMP_DIR/s04.mp4" pan-right
trim_counter         "$CARDS/05_total_counter.mp4" "$slot_total" "$TMP_DIR/s05.mp4"
# Hero slot — aggressive zoom-in on the "ripple" wordmark while music swells.
render_card_kenburns "$CARDS/05b_hero.png"    "$slot_hero"      "$TMP_DIR/s05b.mp4" in

if [[ "$MODE" == "final" ]]; then
  per_clip=$(awk "BEGIN { printf \"%.3f\", $slot_demo / 3 }")
  for n in 1 2 3; do
    clip="$RAW/clip${n}.mov"
    [[ -f "$clip" ]] || { echo "✗ Missing $clip" >&2; exit 1; }
    normalize_clip "$clip" "$per_clip" "$TMP_DIR/s06_${n}.mp4"
  done
  DEMO_SLOTS=( "$TMP_DIR/s06_1.mp4" "$TMP_DIR/s06_2.mp4" "$TMP_DIR/s06_3.mp4" )
else
  render_card_kenburns "$CARDS/06_outro.png"  "$slot_demo"      "$TMP_DIR/s06.mp4"  out
  DEMO_SLOTS=( "$TMP_DIR/s06.mp4" )
fi

render_card_kenburns "$CARDS/06_outro.png" "$slot_outro" "$TMP_DIR/s07.mp4" in

# ── Concat ──────────────────────────────────────────────────────────────────
LIST="$TMP_DIR/concat.txt"
{
  printf "file '%s'\n" "$TMP_DIR/s00.mp4"
  printf "file '%s'\n" "$TMP_DIR/s01.mp4"
  printf "file '%s'\n" "$TMP_DIR/s02.mp4"
  printf "file '%s'\n" "$TMP_DIR/s03.mp4"
  printf "file '%s'\n" "$TMP_DIR/s04.mp4"
  printf "file '%s'\n" "$TMP_DIR/s05.mp4"
  printf "file '%s'\n" "$TMP_DIR/s05b.mp4"
  for d in "${DEMO_SLOTS[@]}"; do printf "file '%s'\n" "$d"; done
  printf "file '%s'\n" "$TMP_DIR/s07.mp4"
} > "$LIST"

echo "→ Mixing audio + burning captions..."

VO_LEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$AUDIO")
FADE_START=$(awk "BEGIN { printf \"%.2f\", $VO_LEN - $FADEOUT }")

# Convert each SFX delay (seconds) into milliseconds for adelay
to_ms() { awk "BEGIN { printf \"%d\", $1 * 1000 }"; }
POP_MS=$(to_ms "$SFX_POP_AT")
WHOOSH_MS=$(to_ms "$SFX_WHOOSH_AT")
DING_MS=$(to_ms "$SFX_DING_AT")
CH1_MS=$(to_ms "$SFX_CHACHING_1_AT")
CH2_MS=$(to_ms "$SFX_CHACHING_2_AT")
CH3_MS=$(to_ms "$SFX_CHACHING_3_AT")

if [[ -f "$BGM" ]]; then
  GAIN=$(awk "BEGIN { printf \"%.4f\", 10^($BGM_DB/20) }")
  # Input map (1-indexed because [0] is the concat'd video):
  #   [1] BGM  (looped)
  #   [2] VO
  #   [3] pop.wav
  #   [4] whoosh.wav
  #   [5] ding.wav
  # BGM is split into TWO streams so we can JUMP forward at the swell-back:
  #   bgm_a  = original BGM from t=0, plays then fades out at duck-out
  #   bgm_b  = original BGM from t=BGM_PEAK_OFFSET, delayed so it starts at
  #            the duck-in moment with a fade-in. This skips the gentle
  #            intro and lands in the loud melody section as music comes back.
  BGM_DELAY_MS=$(to_ms "$BGM_DUCK_IN")

  # Input map:
  #   [0] concat video           [1] BGM (from start)        [2] VO
  #   [3] pop.wav                [4] ding.wav                [5] BGM (peak)
  #   [6] chaching #1 (Flip 7)   [7] chaching #2 (air fryer) [8] chaching #3 (Owala)
  AUDIO_FILTER="\
[1:a]volume=${GAIN},afade=t=out:st=${BGM_DUCK_OUT}:d=${BGM_DUCK_OUT_DUR}:curve=tri[bgm_a];\
[5:a]volume=${GAIN},adelay=${BGM_DELAY_MS}|${BGM_DELAY_MS},\
afade=t=in:st=${BGM_DUCK_IN}:d=${BGM_DUCK_IN_DUR}:curve=tri,\
afade=t=out:st=${FADE_START}:d=${FADEOUT}[bgm_b];\
[3:a]adelay=${POP_MS}|${POP_MS},volume=0.9[pop];\
[4:a]adelay=${DING_MS}|${DING_MS},volume=0.8[di];\
[6:a]adelay=${CH1_MS}|${CH1_MS},volume=0.55[ch1];\
[7:a]adelay=${CH2_MS}|${CH2_MS},volume=0.55[ch2];\
[8:a]adelay=${CH3_MS}|${CH3_MS},volume=0.55[ch3];\
[2:a][bgm_a][bgm_b][pop][di][ch1][ch2][ch3]amix=inputs=8:duration=first:dropout_transition=0:normalize=0,aformat=channel_layouts=stereo[a]"
  EXTRA_INPUTS=( -stream_loop -1 -t "$VO_LEN" -i "$BGM"
                 -i "$AUDIO"
                 -i "$SFX_DIR/pop.wav" -i "$SFX_DIR/ding.wav"
                 -ss "$BGM_PEAK_OFFSET" -stream_loop -1 -t "$VO_LEN" -i "$BGM"
                 -i "$SFX_DIR/chaching.wav"
                 -i "$SFX_DIR/chaching.wav"
                 -i "$SFX_DIR/chaching.wav" )
  AUDIO_MAP=( -map "[a]" )
else
  AUDIO_FILTER=""
  EXTRA_INPUTS=( -i "$AUDIO" )
  AUDIO_MAP=( -map 1:a )
fi

# Captions burned via libass (subtitles filter). Use absolute path so libass
# resolves the file regardless of CWD.
VIDEO_FILTER="[0:v]subtitles='${CAPTIONS}':fontsdir='${FONTSDIR}'[v]"

if [[ -n "$AUDIO_FILTER" ]]; then
  FILTER="${VIDEO_FILTER};${AUDIO_FILTER}"
else
  FILTER="$VIDEO_FILTER"
fi

ffmpeg -y -loglevel warning \
  -f concat -safe 0 -i "$LIST" \
  "${EXTRA_INPUTS[@]}" \
  -filter_complex "$FILTER" \
  -map "[v]" "${AUDIO_MAP[@]}" \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
  -c:a aac -b:a 192k \
  -shortest \
  -movflags +faststart \
  "$OUT"

echo "✓ Done: $OUT"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" | sed 's/^/   duration: /'
