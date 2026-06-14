#!/usr/bin/env python3
"""Build a kinetic ASS subtitle file from whisper-cli's word-level JSON.

Style: CapCut/Submagic-ish. Groups words into 2-3 word chunks; each chunk
snaps in with a scale bounce; positioned lower-third; bold Inter Black with a
hard black outline. Burned into the video by ffmpeg's `subtitles` filter.

Run: python3 scripts/build_captions.py
Outputs: marketing/captions.ass
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
WHISPER_JSON = os.path.join(HERE, '..', 'marketing', 'audio', 'vo_v3.json')
OUT = os.path.join(HERE, '..', 'marketing', 'captions.ass')

# The CANONICAL script — what Eric actually says, with correct spelling and
# punctuation. We borrow only the *timestamps* from Whisper; the text comes
# from here. This eliminates Whisper transcription errors ("co-workers",
# "buys , you", etc.) without losing word-level timing.
SCRIPT = (
    "Stuff my friends bought because I recommended it. "
    "And what I earned for each. "
    "Flip 7. I taught it to my coworkers at lunch. "
    "Six of them bought it within a week. "
    "That air fryer I wouldn't shut up about. "
    "Three friends ordered one. "
    "Owala water bottles. Got my whole family hooked. "
    "Five in one weekend. "
    "Conservatively, forty bucks I would have earned. "
    "If I were anyone's affiliate. I'm not. "
    "But that's why I built Ripple. "
    "Browse to a product. Tap Ripple. Paste it in your group chat. "
    "When a friend buys, you earn a small commission. They pay nothing extra. "
    "Word of mouth, finally rewarded. Link in bio."
)

# Offset captions earlier — Whisper returns *end* timestamps tighter than
# *start*, so they read late in fast speech. Empirically, -200ms feels in-sync.
LEAD_OFFSET_MS = -200

# Extra pre-roll added before the VO (so captions can shift forward by this
# amount when the video has an opening hook segment before the audio starts).
PREROLL_MS = 0

# Suppress captions during this opening window — the bubble graphic conveys
# its own message ("Here's a link to that airfryer") and competing captions
# under it confuse the read.
HOOK_BUBBLE_MS = 1600

# Video dimensions — must match the ffmpeg render
W, H = 1080, 1920

# Caption styling
FONT_NAME = 'Inter Black'
FONT_SIZE = 92
PRIMARY = '&H00FFFFFF'      # white
OUTLINE = '&H00000000'      # black
SHADOW = '&H80000000'
ACCENT_RGB = (248, 189, 56)  # ACCENT_2 (38bdf8) in BGR for ASS — but we want
                              # to highlight active word. Will not use here; uniform white.

# Sentence-ending chars that should force a new chunk
SENT_END = set('.!?')
# Max words per chunk — 2 is the modern Reel/TikTok pacing.
MAX_WORDS = 2
# Min duration per chunk (seconds) — avoid sub-100ms flashes
MIN_DUR = 0.30


def ms_to_ass_time(ms):
    """ms → H:MM:SS.cs format."""
    cs = int(round(ms / 10))
    s, cs = divmod(cs, 100)
    m, s = divmod(s, 60)
    h, m = divmod(m, 60)
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def load_words():
    """Return list of (text, start_ms, end_ms), skipping blanks.

    The *text* comes from SCRIPT (so spelling is right); we only use Whisper's
    word-level timestamps to know *when* each word lands. Whisper emits
    punctuation as its own token, which we drop — punctuation comes from the
    canonical script.
    """
    data = json.load(open(WHISPER_JSON))
    # Whisper splits sub-words: "coworkers" → " co" + "-" + "workers", "I'm" →
    # " I" + "'m", "fryer" → " fry" + "er". A token starts a new spoken word
    # iff its raw text begins with whitespace. Everything else merges back.
    whisper_timings = []
    for seg in data['transcription']:
        raw = seg['text']
        stripped = raw.strip()
        if not stripped:
            continue
        s, e = seg['offsets']['from'], seg['offsets']['to']
        starts_new = raw.startswith((' ', '\n')) or not whisper_timings
        # Pure-punctuation continuation token (like the lone '-' inside
        # "co-workers" or a separate '.') — treat as continuation either way.
        is_punct = all(c in '.,!?;:-\'"' for c in stripped)
        if starts_new and not is_punct:
            whisper_timings.append([s, e])
        else:
            # Extend previous word's end time
            if whisper_timings:
                whisper_timings[-1][1] = e
            else:
                whisper_timings.append([s, e])
    whisper_timings = [tuple(t) for t in whisper_timings]

    # Split the canonical script into whitespace-separated words.
    script_words = SCRIPT.split()

    # Reload raw Whisper text (post-merge) so we can do fuzzy alignment when
    # Whisper splits a script word into multiple tokens (e.g. "Owala" → "a
    # wall of") or vice versa. We walk the script in order; for each script
    # word, take the next whisper token if it phonetically matches, otherwise
    # absorb up to N tokens until we find one that does.
    raw = []
    for seg in data['transcription']:
        text = seg['text']
        stripped = text.strip()
        if not stripped or all(c in '.,!?;:' for c in stripped):
            continue
        s, e = seg['offsets']['from'], seg['offsets']['to']
        starts_new = text.startswith((' ', '\n')) or not raw
        is_punct_cont = all(c in '.,!?;:-\'"' for c in stripped)
        if starts_new and not is_punct_cont:
            raw.append([stripped, s, e])
        else:
            if raw:
                raw[-1][2] = e
                raw[-1][0] += stripped
    # Now `raw` is the same as whisper_timings but with text retained.

    def norm(x):
        return ''.join(c.lower() for c in x if c.isalnum())

    def matches(script_w, whisper_w):
        a, b = norm(script_w), norm(whisper_w)
        if not a or not b:
            return False
        return a == b or a in b or b in a

    out = []
    j = 0
    MAX_LOOKAHEAD = 4
    for sw in script_words:
        if j >= len(raw):
            # No more whisper data — re-use last timing
            if out:
                out.append((sw, out[-1][1], out[-1][2]))
            continue
        if matches(sw, raw[j][0]):
            out.append((sw, raw[j][1], raw[j][2]))
            j += 1
            continue
        # Look ahead a few positions for a match — when found, absorb the
        # intermediate tokens into this script word's timing.
        found = -1
        for k in range(1, MAX_LOOKAHEAD + 1):
            if j + k < len(raw) and matches(sw, raw[j + k][0]):
                found = k
                break
        if found >= 0:
            out.append((sw, raw[j][1], raw[j + found][2]))
            j += found + 1
        else:
            # Fallback — keep current whisper timing for this script word.
            out.append((sw, raw[j][1], raw[j][2]))
            j += 1

    # Apply lead-offset + preroll
    return [(w, max(0, s + LEAD_OFFSET_MS + PREROLL_MS),
             max(0, e + LEAD_OFFSET_MS + PREROLL_MS))
            for (w, s, e) in out]


def group_words(words):
    """Group word stream into chunks of ≤MAX_WORDS, breaking at sentence ends."""
    chunks = []
    cur = []
    for w, s, e in words:
        cur.append((w, s, e))
        ends_sentence = w[-1] in SENT_END if w else False
        if len(cur) >= MAX_WORDS or ends_sentence:
            chunks.append(cur)
            cur = []
    if cur:
        chunks.append(cur)
    return chunks


def chunk_to_event(chunk):
    """Render one chunk as an ASS Dialogue line with snap-in animation."""
    text = ' '.join(w for w, _, _ in chunk).strip()
    start_ms = chunk[0][1]
    end_ms = chunk[-1][2]
    # Enforce min duration so chunks don't flash
    if end_ms - start_ms < MIN_DUR * 1000:
        end_ms = start_ms + int(MIN_DUR * 1000)

    # Snap-in: scale 115% → 100% over 90ms at the start.
    # Then hold. Looks like a "pop" without being cartoony.
    anim = r'{\fad(40,60)\fscx115\fscy115\t(0,90,\fscx100\fscy100)}'

    return (start_ms, end_ms, f"{anim}{text}")


def main():
    words = load_words()
    chunks = group_words(words)
    events = [chunk_to_event(c) for c in chunks]

    # Drop any caption that ends before the bubble exits. For captions that
    # straddle the boundary, push their start to the boundary.
    cleaned = []
    for start_ms, end_ms, text in events:
        if end_ms <= HOOK_BUBBLE_MS:
            continue
        if start_ms < HOOK_BUBBLE_MS:
            start_ms = HOOK_BUBBLE_MS
        cleaned.append((start_ms, end_ms, text))
    events = cleaned

    # ASS header
    play_res_x, play_res_y = W, H
    # Margin from bottom (alignment 2 = bottom center) — push it up to lower third
    margin_v = 480

    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {play_res_x}
PlayResY: {play_res_y}
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Kinetic,{FONT_NAME},{FONT_SIZE},{PRIMARY},{PRIMARY},{OUTLINE},{SHADOW},1,0,0,0,100,100,0,0,1,6,3,2,80,80,{margin_v},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    lines = [header]
    for start_ms, end_ms, text in events:
        lines.append(
            f"Dialogue: 0,{ms_to_ass_time(start_ms)},{ms_to_ass_time(end_ms)},"
            f"Kinetic,,0,0,0,,{text}"
        )

    open(OUT, 'w').write('\n'.join(lines) + '\n')
    print(f"  wrote {OUT}  ({len(events)} chunks from {len(words)} words)")


if __name__ == '__main__':
    main()
