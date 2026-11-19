#!/usr/bin/env python3
"""Assemble the StopLoss demo video: 9 slides + 5 narration clips.

Audio: 0.7 s lead-in silence, 0.6 s gaps between sections, 2.5 s tail
silence. Slide durations are computed from the measured narration lengths
so the video total matches the audio total exactly. Slides fade in/out
(0.4 s) at each cut.
"""
import json
import subprocess
import os

D = "/home/hatch/workspace/dorahacks-reactive/demo-video"
S = f"{D}/slides"
A = f"{D}/audio"
WORK = f"{D}/work"
os.makedirs(WORK, exist_ok=True)

LEAD, GAP, TAIL = 0.7, 0.6, 2.5


def run(cmd, **kw):
    print("+", " ".join(cmd[:6]), "..." if len(cmd) > 6 else "")
    subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def probe_dur(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "json", path],
        capture_output=True, text=True, check=True)
    return float(json.loads(out.stdout)["format"]["duration"])


# 0. Decode TTS MP3s to WAV first (direct MP3 concat produced a corrupt
# 38,263 s duration on the Aevum build — bad MP3 timestamps).
for n in ["s1", "s2", "s3", "s4", "s5"]:
    run(["ffmpeg", "-y", "-v", "error", "-i", f"{A}/{n}.mp3",
         "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le",
         f"{WORK}/{n}.wav"])
dur = {n: probe_dur(f"{WORK}/{n}.wav") for n in ["s1", "s2", "s3", "s4", "s5"]}
print("narration durations:", {k: round(v, 2) for k, v in dur.items()})

# Slide durations: each section's audio is split across its slides; the
# gap after a section is charged to that section's last slide.
SLIDES = [
    ("01_title.png", LEAD + 0.5 * dur["s1"]),
    ("02_problem.png", 0.5 * dur["s1"] + GAP),
    ("03_architecture.png", dur["s2"] + GAP),
    ("04_order.png", 0.5 * dur["s3"]),
    ("05_crash.png", 0.5 * dur["s3"] + GAP),
    ("06_reactive.png", 0.5 * dur["s4"]),
    ("07_callback.png", 0.5 * dur["s4"] + GAP),
    ("08_trust.png", 0.55 * dur["s5"]),
    ("09_close.png", 0.45 * dur["s5"] + TAIL),
]
total = sum(d for _, d in SLIDES)
print(f"video total: {total:.2f}s")

# 1. Per-slide segments (fade in/out, 30 fps, yuv420p).
segs = []
for i, (img, d) in enumerate(SLIDES, 1):
    out = f"{WORK}/seg{i:02d}.mp4"
    run(["ffmpeg", "-y", "-v", "error", "-loop", "1", "-t", f"{d:.3f}",
         "-i", f"{S}/{img}",
         "-vf", (f"scale=1280:720:force_original_aspect_ratio=decrease,"
                 f"pad=1280:720:(ow-iw)/2:(oh-ih)/2,"
                 f"fade=t=in:st=0:d=0.4,fade=t=out:st={d-0.4:.2f}:d=0.4,"
                 f"format=yuv420p"),
         "-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
         "-pix_fmt", "yuv420p", out])
    segs.append(out)
    print(f"segment {i}: {img} {d:.2f}s")

# 2. Concatenate video segments.
with open(f"{WORK}/video_list.txt", "w") as f:
    for s in segs:
        f.write(f"file '{s}'\n")
run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0",
     "-i", f"{WORK}/video_list.txt", "-c", "copy", f"{WORK}/video_only.mp4"])
print("video concat ok")

# 3. Silence beds + full narration track (WAV-only concat).
for name, d in [("sil07", LEAD), ("sil06", GAP), ("sil25", TAIL)]:
    run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
         "-i", "anullsrc=r=44100:cl=stereo", "-t", str(d),
         f"{WORK}/{name}.wav"])
order = ["sil07", "s1", "sil06", "s2", "sil06", "s3", "sil06", "s4",
         "sil06", "s5", "sil25"]
with open(f"{WORK}/audio_list.txt", "w") as f:
    for n in order:
        f.write(f"file '{WORK}/{n}.wav'\n")
run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0",
     "-i", f"{WORK}/audio_list.txt", "-c:a", "aac", "-b:a", "192k",
     f"{WORK}/narration_full.m4a"])
print("audio concat ok")

# 4. Mux + faststart.
run(["ffmpeg", "-y", "-v", "error", "-i", f"{WORK}/video_only.mp4",
     "-i", f"{WORK}/narration_full.m4a",
     "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "copy",
     "-movflags", "+faststart", "-shortest", f"{D}/stoploss-demo.mp4"])
print("mux ok ->", f"{D}/stoploss-demo.mp4")
