# Decoder regression fixtures

These five small media files contain four seconds of synthetic stereo chirps,
two sine tones and low-level deterministic noise, generated for this project.
They contain no third-party recording. The generated signal and fixture files
are dedicated to the public domain (CC0-1.0).

At 44,100 frames/second, for `t = frame / 44100`:

```
envelope = 0.55 + 0.35 * sin(2*pi*1.7*t)
noise = Python random.Random(683741).uniform(-1,1) * 0.004
L = envelope * (0.20*sin(2*pi*(300*t+300*t*t)) + 0.15*sin(2*pi*740*t)) + noise
R = envelope * (0.19*sin(2*pi*(431*t+93*t*t)) + 0.14*sin(2*pi*1260*t)) - noise
```

Each channel was converted to signed 16-bit PCM with `int(value * 32767)`.
FFmpeg was used solely as a fixture-generation tool, with `-map_metadata -1`:

| File | Encoder options | SHA-256 |
| --- | --- | --- |
| stereo_vbr.mp3 | `-c:a libmp3lame -q:a 5` | `6805d249a95f49f79c81627b01e6d27ce620365d7264547e98347404c6598327` |
| mono_mpeg2.mp3 | `-ar 22050 -ac 1 -c:a libmp3lame -b:a 32k` | `662ce953c38c1641e7ed7a2281a6f198f804dbd919fad4be40d19d1ff9d39801` |
| mono_mpeg25.mp3 | `-ar 11025 -ac 1 -c:a libmp3lame -b:a 16k` | `5e9171e9a922d4773a9e7b2ae91bc4527aeeb671587b59a4941c4a022fb97b0d` |
| stereo_lc.aac | `-c:a aac -b:a 64k -f adts` | `9c80ff04f4a8e98795d0c03ce107e6fe8f277496c959c9dee98f8caf7e1ca07f` |
| stereo_lc.m4b | `-c:a aac -b:a 64k -movflags +faststart -f mp4` | `d34889b3c15b2fa497a68bdd84700d2c7366fcd49d200a0149800f692a443582` |

Tests decode these files using the actual bundled Glint implementation, check
presentation lengths and gapless trimming, and compare arbitrary seeks against
sequential PCM from the same stream. The two lower-rate MP3 fixtures exercise
MPEG-2 and MPEG-2.5. AAC tests exercise deterministic per-packet PNS state.
Tests do not depend on a system FFmpeg installation and the application does
not execute it.
