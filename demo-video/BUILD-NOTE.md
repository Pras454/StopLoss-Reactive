# Demo video — build note

Built 19 Nov 2026. Deliverable: `stoploss-demo.mp4`
(1280x720, h264 + AAC, 30 fps, **123.44 s ≈ 2:03**, 4.3 MB, faststart).

## Sources

- All facts, addresses and tx hashes come from
  `~/workspace/dorahacks-reactive/DEMO.md` (live demo run 19 Nov 2026,
  verified on-chain). Nothing was invented: order #0 0.003 WETH, stop
  $26,796.33 (0.5% below $26,930.98), trigger sell 0.008 WETH →
  $26,624.35 (−1.14%), reactive tx 0xb82dff8d… (Lasna block 8702783),
  callback tx 0x92c19a29… (Base Sepolia block 60684787, 10 blocks / ~20 s
  later), 79.757622 USDC paid. Contract addresses + Sourcify status from
  DEMO.md / BUILD.md; test count (19/19) from BUILD.md.
- Narration script: `narration-script.md` (~370 words, 5 sections).
  Synthesized per section with `/opt/hatch/bin/tts speak` (voice Helio,
  default `avocado_v2:MAI_03`, language `en`) → `audio/s1.mp3` … `s5.mp3`
  (14.81 / 32.09 / 24.60 / 29.47 / 16.87 s).
- Slides: `make_slides.py` (PIL, DejaVu fonts) renders 9 cards, including
  the architecture diagram (pool → Swap log → RSC on Lasna → callback →
  vault) and full tx hashes on the crash / reactive / callback cards.
  One fix during build: the "callback via proxy" label overlapped the
  diagonal arrow on the architecture slide — moved right of the line.

## What is NOT in the video

- No live explorer screenshots (Playwright Chromium cannot reach external
  HTTPS from this VM — same failure as the Aevum build). The tx slides are
  PIL cards carrying the exact hashes, blocks and figures from DEMO.md.
- No UI screenshot — the demo UI is being built in parallel by another
  worker; the video tells the story with diagram + on-chain evidence cards.
- No GitHub repo URL — the repo does not exist yet (Bagus creates the empty
  repo; the token cannot). Add it to the DoraHacks submission form, not
  the video.

## Assembly (`build_video.py`, ffmpeg 8.1.2)

1. Slide durations are computed from the measured narration lengths
   (ffprobe on the decoded WAVs): title 8.10, problem 8.00, architecture
   32.69, order 12.30, crash 12.90, reactive 14.74, callback 15.34, trust
   9.28, close 10.09 — total 123.44 s, exactly matching the audio.
2. Each slide → one segment: `-loop 1 -t <dur>`, scale/pad to 1280x720,
   `fade=t=in:st=0:d=0.4` + `fade=t=out:st=<dur-0.4>:d=0.4`, libx264 CRF 20.
3. Segments concatenated (concat demuxer, stream copy).
4. Audio: silence beds from `anullsrc` (0.7 s lead, 0.6 s between sections,
   2.5 s tail); **MP3s decoded to 44.1 kHz stereo WAV first** — direct MP3
   concat produced a corrupt 38,263 s duration on the Aevum build. WAV-only
   concat → AAC 192k, exactly 123.44 s.
5. Mux: `-c:v copy -c:a copy -movflags +faststart -shortest`.

## Verification

- `ffprobe`: 123.44 s, video h264 1280x720 30 fps, audio AAC.
- `volumedetect`: mean −31.7 dB, max −8.5 dB (speech present, no clipping).
- Frames extracted at t=3/12/30/55/70/85/100/118 and visually checked:
  title, architecture (label fix confirmed), order, crash, reactive,
  callback, close — all correct, readable, and in sync with narration.

## Notes

- No private key appears anywhere in the video or its sources:
  `deployer-keypair.json` was never opened. Only public addresses / tx hashes.
- Testnet only; no real-money value is mentioned.
- Rebuild: `python3 make_slides.py && python3 build_video.py`
