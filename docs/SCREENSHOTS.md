# Screenshot Checklist — CrisperPlayer

> Last updated: 2026-10-17 • v0.1.0 • Source-of-truth for store visual assets.
> Companion: [`../STORE_LISTING.md`](../STORE_LISTING.md) (Play + App Store metadata, descriptions, data-safety).

This document is the complete checklist for producing **Google Play** and **Apple App Store** screenshots, icons, and feature graphics. All specs reflect the current [Play Console](https://play.google.com/console) and [App Store Connect](https://appstoreconnect.apple.com) requirements as of Oct 2026. Tick boxes (☐→☑) when assets are captured, reviewed, and uploaded.

---

## Quick links

- [Play — Phone](#google-play-store) | [Play — Tablet](#tablet-screenshots-optional-but-recommended) | [Play — Feature graphic & icon](#feature-graphic-required)
- [App Store — iPhone 6.7″](#iphone-67-required--iphone-15-pro-max--16-pro-max) | [6.5″](#iphone-65-required--iphone-11-pro-max--xs-max) | [5.5″](#iphone-55-recommended--iphone-8-plus) | [iPad 12.9″](#ipad-129-required-if-ipad-supported)
- [Capture workflow](#capture-workflow) | [Output layout](#output-layout--naming) | [Best practices](#screenshot-best-practices) | [Review gate](#pre-upload-review-gate)

---

## Google Play Store

### Phone screenshots (required — min 2, max 8)

Play displays screenshots in upload order; first 2 are visible in search. Use **portrait 9:16**.

| # | Screen | Device spec | What to show | Status |
|---|---|---|---|---|
| 1 | Library | 1080 × 2340 px (or 1440 × 3120) | Grid of 4–6 audiobook covers with progress bars, search, sort/filter chip | ☐ |
| 2 | Player | 1080 × 2340 px | Cover art, title, author, chapter, progress bar, play/pause, skip ±30 s, speed, sleep timer | ☐ |
| 3 | Chapters | 1080 × 2340 px | Chapter list sheet with current chapter highlighted + chapter progress dots | ☐ |
| 4 | Bookmarks | 1080 × 2340 px | Bookmarks list (manual + auto) with title, note, timestamp, tap-to-seek | ☐ |
| 5 | History | 1080 × 2340 px | Listening history grouped by day — duration, book title, time range | ☐ |
| 6 | Settings | 1080 × 2340 px | Settings: speed, skip silence, seek interval, auto-bookmark, resume, theme (light/dark) | ☐ |
| 7 | Onboarding | 1080 × 2340 px | First-launch walkthrough (3 pages: import → permissions → done) | ☐ |
| 8 | Notification | 1080 × 2340 px | Android notification shade with playback controls, lock-screen art | ☐ |

Accepted: JPEG or PNG, 320–3840 px per side, 16:9 or 9:16. **No alpha** in JPEG. Max 8.

### Tablet screenshots (optional but recommended)

Upload under Play Console → *Tablet* track. Improves tablet featuring and "Optimized for tablets" badge.

| Screen | Spec | Notes | Status |
|---|---|---|---|
| Library (7″) | 1200 × 1920 px (W×H) | Portrait; grid shows 3 columns | ☐ |
| Library (10″) | 1600 × 2560 px | Portrait or landscape (Play accepts both); grid shows 4 columns | ☐ |
| Player (10″) | 1600 × 2560 px | Expanded controls, cover left / controls right on landscape | ☐ |

If skipped, phone screenshots are shown letter-boxed on tablets — not ideal.

### Feature graphic (required)

| Asset | Spec | Notes | Status |
|---|---|---|---|
| Feature graphic | 1024 × 500 PNG or JPEG | No alpha. Safe text area: center 924 × 400. Shown in Play search, pre-registration, and promo cards. | ☐ |

Keep text large, ≤10 words. Export at 100% quality PNG or high-quality JPEG.

### App icon (required)

| Asset | Spec | Notes | Status |
|---|---|---|---|
| High-res icon | 512 × 512 PNG (32-bit, **no alpha channel**) | Matches `android/app/src/main/res/mipmap-*` launcher icons. Must not contain device frame or Play badge. | ☐ |

---

## Apple App Store

Screenshots are per **size class** in App Store Connect. Upload the highest-required size; Apple downscales automatically. All screenshots must be **PNG, no alpha**, no device bezels or status-bar edits beyond Apple guidelines.

### iPhone 6.7″ (required — iPhone 15 Pro Max / 16 Pro Max)

Primary for iOS 17/18 display. Required if you support iPhone.

| # | Screen | Spec | Status |
|---|---|---|---|
| 1 | Library | 1290 × 2796 px | ☐ |
| 2 | Player | 1290 × 2796 px | ☐ |
| 3 | Chapters | 1290 × 2796 px | ☐ |
| 4 | Bookmarks | 1290 × 2796 px | ☐ |
| 5 | History | 1290 × 2796 px | ☐ |
| 6 | Settings | 1290 × 2796 px | ☐ |

Portrait required; landscape accepted only for landscape-only apps. Min 1, max 10 per size class.

### iPhone 6.5″ (required — iPhone 11 Pro Max / XS Max)

Still required for backward compatibility — App Store Connect will not clear "Missing screenshots" without it.

| # | Screen | Spec | Status |
|---|---|---|---|
| 1 | Library | 1284 × 2778 px | ☐ |
| 2 | Player | 1284 × 2778 px | ☐ |
| 3 | Chapters | 1284 × 2778 px | ☐ |
| 4 | Bookmarks | 1284 × 2778 px | ☐ |
| 5 | History | 1284 × 2778 px | ☐ |
| 6 | Settings | 1284 × 2778 px | ☐ |

### iPhone 5.5″ (recommended — iPhone 8 Plus)

Shown on legacy App Store clients; upload to avoid letterboxing on older OS.

| # | Screen | Spec | Status |
|---|---|---|---|
| 1 | Library | 1242 × 2208 px | ☐ |
| 2 | Player | 1242 × 2208 px | ☐ |
| 3 | Chapters | 1242 × 2208 px | ☐ |
| 4 | Bookmarks | 1242 × 2208 px | ☐ |
| 5 | History | 1242 × 2208 px | ☐ |
| 6 | Settings | 1242 × 2208 px | ☐ |

### iPad 12.9″ (required if iPad supported)

App declares `UISupportedInterfaceOrientations~ipad` (see `ios/Runner/Info.plist`). Therefore iPad screenshots are **required** for review.

| # | Screen | Spec | Notes | Status |
|---|---|---|---|---|
| 1 | Library | 2048 × 2732 px | 12.9″ 2nd–6th gen, portrait | ☐ |
| 2 | Player | 2048 × 2732 px | Cover + controls, respects split-view safe area | ☐ |
| 3 | Settings | 2048 × 2732 px | Larger type, grouped sections | ☐ |

For iPad, also acceptable: `2732 × 2048` (landscape) if app is universal — include one set.

### App icon (required)

| Asset | Spec | Notes | Status |
|---|---|---|---|
| App icon | 1024 × 1024 PNG (no alpha, no rounded corners) | Apple adds masking. Must match App Store icon in Xcode asset catalog. | ☐ |

### App preview video (optional)

| Asset | Spec | Status |
|---|---|---|
| Preview (iPhone) | 1920 × 1080 or 886 × 1920, H.264, 15–30 s, ≤500 MB | ☐ |
| Poster frame | Auto-extracted; verify first frame is not black | ☐ |

---

## Capture workflow

### Prerequisite: seed data

Populate the app with 3–5 public-domain audiobooks so the library grid looks natural and progress/history are non-empty:

```bash
# Generate or copy sample audiobook files into emulator/simulator storage
flutter run -d <device>
# Then import via Library → Import → select m4b/mp3 files
# Or seed programmatically:
dart run tool/seed_sample.dart
```

Ensure at least one book is partially played (≈30–60%) to show progress bars; add 2–3 manual bookmarks and one listening-history session.

### Device & emulator definitions

| Store track | Recommended AVD / Simulator |
|---|---|
| Play Phone | Pixel 7 (1080 × 2400) or Pixel 8 Pro (1344 × 2992) — screenshot auto-scales; verify 320–3840 bounds |
| Play 7″ tablet | Nexus 7 (1200 × 1920) AVD, API 34 |
| Play 10″ tablet | Pixel Tablet (1600 × 2560) AVD, API 34 |
| iPhone 6.7″ | iPhone 15 Pro Max simulator (iOS 17.5+) |
| iPhone 6.5″ | iPhone 11 Pro Max simulator (iOS 16+) |
| iPhone 5.5″ | iPhone 8 Plus simulator (iOS 16+) |
| iPad 12.9″ | iPad Pro 12.9″ (6th gen) simulator (iPadOS 17+) |

Use **100% scale, light mode + dark mode pass**, status bar: 9:41 AM, full battery, Wi-Fi, no carrier text.

### Manual capture

```bash
# Android — after navigating to desired screen:
adb exec-out screencap -p > screenshots/phone-library.png

# iOS Simulator — Device → Screenshot (Cmd+S), or:
xcrun simctl io booted screenshot screenshots/iphone67-library.png
```

Crop/resize to exact spec if needed (use `sips` on macOS or `convert` via ImageMagick):

```bash
# macOS example — resize with no re-encode loss:
sips -z 2796 1290 screenshots/iphone67-library.png --out screenshots/iphone67-library.png
```

### Automated capture (recommended for CI)

Use `integration_test/app_test.dart` screenshot hooks or `flutter test` driver:

```bash
# WIP: wire screenshots into integration test via takeScreenshot
flutter test integration_test/app_test.dart -d <device> --dart-define=SCREENSHOTS=true
# Artifacts land in build/screenshots/
```

For bulk generation, *fastlane* lanes (`fastlane snapshot` / `screengrab`) can drive simulators/AVDs and rename outputs to `docs/screenshots/<track>/`.

---

## Output layout & naming

Store raw captures under `docs/screenshots/` (gitignored until final review — see `.gitignore` build/ rule; commit final PNGs):

```
docs/screenshots/
  play-phone/          # 1080x2340
    01-library.png
    02-player.png
    ...
  play-tablet-7/       # 1200x1920
  play-tablet-10/      # 1600x2560
  play-feature/
    feature-graphic-1024x500.png
  appstore-iphone67/   # 1290x2796
  appstore-iphone65/   # 1284x2778
  appstore-iphone55/   # 1242x2208
  appstore-ipad129/    # 2048x2732
  icons/
    play-icon-512.png
    appstore-icon-1024.png
```

Naming: `NN-screen-device.png` (e.g., `02-player-iphone67.png`). Keep original PNG-24, no interlacing.

---

## Screenshot best practices

- **Use real data** — populate with 3–5 public-domain audiobooks (e.g., LibriVox). Avoid copyrighted bestseller covers unless licensed.
- **Show progress** — one partially-read book (40–70%) demonstrates resume/progress feature.
- **Dark mode** — include at least one dark-mode screenshot (settings or player) to showcase theme support.
- **No personal data** — no real names, personal photos, private file paths, or personal book titles.
- **No frames or marketing overlays** — Play/App Store forbid device bezels, badges, or "Best App" banners in screenshots.
- **Consistent device** — same device model per size class; status bar clean (9:41 AM, full signal/battery).
- **JPEG or PNG** — Play accepts both (PNG preferred for text sharpness); App Store **requires PNG**.
- **Feature graphic text** — ≤10 words, 30% center safe area, high contrast, no Play Store badge.
- **Accessibility** — ensure screenshots meet WCAG contrast; test on color-blind preview.

---

## Pre-upload review gate

Before uploading, verify each asset:

- [ ] Dimensions match spec exactly (Play is strict; App Store rejects off-by-1).
- [ ] No alpha channel where forbidden (Play icon, App Store icon/feature graphic).
- [ ] File size sane (<5 MB per screenshot, <10 MB feature graphic).
- [ ] No trademarked/copied store badges inside screenshots.
- [ ] No placeholder "lorem ipsum" or empty states — every screenshot shows populated UI.
- [ ] Privacy: no PII, no real e-mail/file-path, no copyrighted cover without rights.
- [ ] Dark mode represented at least once.
- [ ] Ordered for impact: Library → Player → Chapters → Bookmarks → History → Settings.

Common rejection reasons: wrong dimensions, alpha in icon, copyrighted cover art, empty library screenshot, incorrect iPad requirement.

---

## Related

- Store copy, descriptions, keywords, data-safety: [`../STORE_LISTING.md`](../STORE_LISTING.md)
- Android build & signing: [`ANDROID_BUILD.md`](ANDROID_BUILD.md)
- iOS build & signing: [`IOS_BUILD.md`](IOS_BUILD.md)
- Performance notes: [`PERFORMANCE.md`](PERFORMANCE.md)

