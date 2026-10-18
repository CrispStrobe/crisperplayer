# CrisperPlayer — Store Listing

> Last updated: 2026-10-17 • v0.1.0+1 • Package `com.crispstrobe.crisperplayer`
> Screenshots checklist: [`docs/SCREENSHOTS.md`](docs/SCREENSHOTS.md) • Android build: [`docs/ANDROID_BUILD.md`](docs/ANDROID_BUILD.md) • iOS build: [`docs/IOS_BUILD.md`](docs/IOS_BUILD.md)

Single source of truth for copy that ships to **Google Play Console** and **Apple App Store Connect**. Keep short/long descriptions, keywords, and visual specs in sync between the two stores. Descriptions are UTF-8 plain text — no Markdown in console fields (bullets use `•`).

---

## Google Play Store

### App basics

| Field | Value | Notes |
|---|---|---|
| **Title** (50 chars) | CrisperPlayer — Audiobook Player | 32 chars, keyword-rich |
| **Short description** (80 chars) | Play m4b/m4a/mp3/flac/ogg offline. Resume, bookmarks, history, sleep timer. | 73/80 — verified |
| **Long description** (4000 chars max) | See below | ~1520 chars, under limit |
| **Package** | `com.crispstrobe.crisperplayer` | From `android/app/build.gradle.kts` |
| **Category** | Music & Audio | Primary |
| **Tags** | Audiobook, Offline, Player | Console tags (max 5) |
| **Content rating** | Everyone | After questionnaire (see below) |
| **Target audience** | Adults (audiobook listeners) | No child-directed content |
| **Price** | Free, no IAP | No ads |
| **Countries** | All (150+) | No geo restrictions |

### Long description (Play Store)

Paste verbatim into Play Console → *Main store listing* → *Full description* (no Markdown):

```
CrisperPlayer is a versatile offline audiobook player for Android.

FORMATS
Native decoders handle m4b/m4a (with Nero chpl chapter support and cover art), plus mp3, flac, ogg, wav, aac, opus, wma, and aiff. Import your own files — no streaming, no accounts, no ads.

FEATURES
• Library — grid view with reading progress, search, sort by title/author/date, multi-file book import
• Chapters — m4b chapter navigation, chapter progress bar, chapter list sheet
• Resume — automatic position restore on app relaunch, per-book memory
• Listening history — grouped by day, see when you played what
• Bookmarks — manual (title + note) and auto (5-min ticker + on pause), tap to seek, edit/delete
• Sleep timer — 15/30/60 minutes or end-of-chapter, fade-out
• Playback — skip +/-30s, speed 0.5–3x, smart rewind, skip silence option
• Background playback — lock screen and notification controls
• Export/Import — backup library, bookmarks, and history as JSON
• Onboarding — first-launch walkthrough
• Themes — light, dark, and system

PRIVACY
No network access. No tracking. No analytics. All data stays on your device. Export is local JSON — you control where it goes.

Perfect for commuters, runners, and anyone who listens to audiobooks offline.
```

### Play Store visual assets

| Asset | Spec | Required | Status |
|---|---|---|---|
| App icon | 512 × 512 PNG (32-bit, **no alpha**) | Required | ☐ |
| Feature graphic | 1024 × 500 PNG or JPEG | Required | ☐ |
| Phone screenshots | Min 2, max 8; 320–3840 px, 16:9 or 9:16 | Required | ☐ — see checklist |
| Tablet screenshots (7″ & 10″) | 1200×1920, 1600×2560 | Optional but recommended | ☐ |

See full checklist + device specs: [`docs/SCREENSHOTS.md`](docs/SCREENSHOTS.md).

### Content rating questionnaire (IARC)

| Category | Answer | Justification |
|---|---|---|
| Violence / Fear | None | Utility player, no media content |
| Profanity / Crude humour | None |  |
| Sexual content / Nudity | None |  |
| Controlled substances | None |  |
| Gambling | None |  |
| User-generated content | No | No social, no sharing, no chat |
| User-to-user communication | No |  |
| Ads | No ads | No SDK ads |
| In-app purchases | None |  |
| Location sharing | None | No location permission |
| Personal info collection | None | Offline-only |

→ Expected rating: **Everyone** (ESRB: Everyone, PEGI: 3, etc.)

### Data safety (Play Console → Data safety form)

Complete the Data safety declaration before submitting. CrisperPlayer is **offline-first** — no data leaves the device.

| Question | Answer |
|---|---|
| Does app collect or share user data? | **No** |
| Is all user data encrypted in transit? | N/A (no transit) — answer *Yes* (HTTPS not applicable, no transmission) |
| Can users request data deletion? | **Yes** — Settings → Export/Import → Clear data; uninstall also deletes DB |
| Data types collected | **None** (no location, contacts, files shared externally, browsing history, diagnostics off-device) |
| Purpose | N/A |
| SDKs / third-party sharing | **None** — no analytics, crashlytics, ads, auth |

If the form requires at least one “Data collected” entry, declare **“App activity → files & docs — on-device only, not collected”** and note in review comments that import is via `file_picker` → local Drift DB only.

Keep the Data safety answer in sync with the privacy policy URL.

### Permissions declared (Google Play “App permissions” tab)

Derived from `android/app/src/main/AndroidManifest.xml` (verified 2026-10-17):

| Permission | Declared in manifest | Runtime request | Purpose | Store disclosure |
|---|---|---|---|---|
| `READ_EXTERNAL_STORAGE` (`maxSdkVersion=32`) | Yes (legacy, API ≤32) | via `permission_handler` → `Permission.audio` fallback | Read user-selected audiobook files on Android 12 and below | “Access audio files on device — you pick which files to import” |
| `READ_MEDIA_AUDIO` | Yes | via `Permission.audio` (API 33+) | Read user-selected audiobook files on Android 13+ | Same as above |
| `FOREGROUND_SERVICE` | Yes | — (install grant) | Background playback service (`audio_service`) | “Play audiobooks with screen off / in background” |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Yes | — (requires FOREGROUND_SERVICE) | Scoped foreground type for media (API 34+) | Same — shown as part of foreground service |
| `POST_NOTIFICATIONS` | Yes | via `Permission.notification` (API 33+) | Playback notification with controls | “Show playback controls in notification / lock screen” |
| `WAKE_LOCK` | Yes | — | Keep audio playing when screen off | Implicit, not user-visible |

No `INTERNET`, `RECORD_AUDIO`, `CAMERA`, `ACCESS_FINE_LOCATION`, or `READ_MEDIA_IMAGES/VIDEO` — therefore no extra questionnaire items. `android:usesCleartextTraffic` and `requestLegacyExternalStorage` remain only if needed for legacy pickers; no network traffic is generated.

Onboarding requests `notification` + `audio` together (`lib/screens/onboarding_screen.dart`); denied permissions are non-fatal — app still plays with degraded notification UX.

---

## Apple App Store

### App basics

| Field | Value | Notes |
|---|---|---|
| **App name** (30 chars) | CrisperPlayer | 13/30 |
| **Subtitle** (30 chars) | Offline Audiobook Player | 24/30 |
| **Promo text** (170 chars) | Offline m4b/mp3/flac player. Chapters, cover art, resume, bookmarks, history & sleep timer. No ads, no tracking — your files stay on your device. | 143/170 — shown above description, editable without review |
| **Description** (4000 chars) | See below | ~1270 chars |
| **Keywords** (100 chars) | audiobook,player,m4b,m4a,mp3,flac,offline,bookmark,sleep | 56/100 |
| **Category** | **Music** | Primary; secondary: *Books* |
| **Age rating** | **4+** | No objectionable content |
| **Copyright** | © 2026 CrisperPlayer |  |
| **Bundle ID** | `com.crispstrobe.crisperplayer` | From Xcode / Runner |
| **SKU** | `crisperplayer-ios-001` | Or preferred prefix |
| **Support URL** | https://github.com/crisperplayer/crisperplayer/issues | Required |
| **Marketing URL** | https://github.com/crisperplayer/crisperplayer | Optional |
| **Privacy policy URL** | https://github.com/crisperplayer/crisperplayer/blob/master/PRIVACY.md | Required — must be live |

### Description (App Store)

Paste into App Store Connect → *App Information* → *Description*:

```
CrisperPlayer is a versatile offline audiobook player for iOS.

FORMATS
Native decoders handle m4b/m4a (with chapter support and cover art), plus mp3, flac, ogg, wav, aac, opus, wma, and aiff. Import your own files — no streaming, no accounts, no ads.

FEATURES
• Library — grid view with reading progress, search, sort, multi-file book import
• Chapters — m4b chapter navigation, chapter progress bar, chapter list
• Resume — automatic position restore on app relaunch
• Listening history — grouped by day
• Bookmarks — manual (title + note) and auto, tap to seek, edit/delete
• Sleep timer — 15/30/60 minutes or end-of-chapter
• Playback — skip +/-30s, speed 0.5–3x, smart rewind
• Background playback — lock screen and Control Center controls
• Export/Import — backup as JSON
• Themes — light, dark, and system

PRIVACY
No network access. No tracking. No analytics. All data stays on your device.

Perfect for commuters, runners, and anyone who listens to audiobooks offline.
```

### App Store visual assets

| Asset | Spec | Required | Status |
|---|---|---|---|
| App icon | 1024 × 1024 PNG (no alpha, no rounded mask) | Required | ☐ |
| iPhone 6.7″ screenshots | 1290 × 2796 px | Required | ☐ |
| iPhone 6.5″ screenshots | 1284 × 2778 px | Required | ☐ |
| iPhone 5.5″ screenshots | 1242 × 2208 px | Recommended | ☐ |
| iPad 12.9″ screenshots | 2048 × 2732 px | Required if iPad supported (this app does) | ☐ |
| App preview video | Optional, H.264 15–30 s | Optional | ☐ |

Full checklist: [`docs/SCREENSHOTS.md`](docs/SCREENSHOTS.md). iPad is required because `UISupportedInterfaceOrientations~ipad` is declared.

### iOS permissions & background modes

Declared in `ios/Runner/Info.plist` (verified 2026-10-17):

| Key | Value | Purpose | User-visible prompt |
|---|---|---|---|
| `UIBackgroundModes = audio` | `<string>audio</string>` | Background playback via `audio_service` + `AVAudioSessionCategory.playback` | None (capability) |
| `NSAppleMusicUsageDescription` | “CrisperPlayer plays audiobooks … shown on lock screen …” | Lockscreen / Control Center metadata (required even without library browsing) | System dialog if triggered |

No `NSPhotoLibraryUsageDescription`, `NSMicrophoneUsageDescription`, `NSCameraUsageDescription` — file import uses `UIDocumentPickerViewController` (no photo-library permission on iOS 15+). No tracking (`NSUserTrackingUsageDescription` not declared).

### App Privacy (App Store Connect → App Privacy → Nutrition Label)

| Question | Answer |
|---|---|
| Data collected from user? | **No — Data Not Collected** |
| Data linked to identity? | **No** |
| Data used for tracking? | **No** |
| Third-party SDKs collecting data? | **None** |

Select **“No, we do not collect data from this app”** as the top-level answer. If the wizard requires detail, enumerate: audio files (user-provided, on-device), listening history/bookmarks (on-device Drift DB), no transmission.

Provide privacy policy covering: (a) file import is on-device, (b) no analytics/ads, (c) export is local JSON, (d) deletion via app or uninstall.

### Review notes (App Store Connect → Review Notes)

Include to speed review:

```
Test account: none — offline app, no login.
To test:
1. Tap Library → Import → pick any m4b/mp3/flac (sample files OK).
2. Play — background: lock screen shows controls.
3. Bookmarks → add → tap to seek.
4. Sleep timer → 15 min or End-of-Chapter.
No network calls. All data on device. For m4b chapters, chapters are parsed from Nero chpl atom.
Contact: https://github.com/crisperplayer/crisperplayer/issues
```

Attach a demo video if iPad background-audio is questioned.

---

## Localization plan

v0.1 ships **en-US** only. Prepared for l10n via `flutter_localizations` (`lib/l10n/` → ARB):

| Locale | Title | Short desc | Long desc | Keywords | Status |
|---|---|---|---|---|---|
| en-US | CrisperPlayer — Audiobook Player | Play m4b/m4a… | Full (above) | audiobook,player,… | ✅ v0.1 |
| en-GB | — | — | — | — | Planned |
| de-DE | — | — | — | — | Planned |
| fr-FR | — | — | — | — | Planned |

When localizing, translate short (≤80C) and long descriptions *and* re-capture screenshots with locale UI. Keep ASO keywords locale-specific.

---

## ASO keywords notes

- Play: title + short desc carry most weight; repeat `audiobook`/`m4b`/`offline` naturally in long description.
- Apple: 100-char comma-separated keywords; no spaces required after comma. Avoid trademark terms, avoid repeating title words (Apple ignores duplicates).
- Both stores: no keyword stuffing — keep readable.

---

## What's new

### v0.1.0 (initial release — current)

```
Initial release — m4b chapters, cover art, resume, bookmarks, history, sleep timer, background playback.
```

Library grid with progress, sort/filter, import (single & multi-file), chapter navigation (Nero chpl + per-file fallback), manual & auto bookmarks, listening history by day, 15/30/60/EoC sleep timer, skip ±30 s, speed 0.5–3×, smart rewind, background/Control Center controls, JSON export/import, onboarding, light/dark/system themes.

### Next (planned)

- Streaming header scan for >500 MB m4b (avoid full `readAsBytes`)
- App preview video + feature graphic final
- Widget / watch complications
- Per-book equalizer / volume boost

---

## Submission checklist

### Google Play

- [ ] App bundle `app-release.aab` signed with upload key (not debug) — see `docs/ANDROID_BUILD.md`
- [ ] Short + long descriptions pasted, ≤80 / ≤4000 chars verified
- [ ] High-res icon (512) + feature graphic (1024×500) uploaded
- [ ] Phone screenshots (2–8) uploaded; tablet screenshots added
- [ ] Content rating questionnaire completed → Everyone
- [ ] Data safety form completed (no collection)
- [ ] Target audience & content → Adults, no child-directed
- [ ] Pricing & distribution → all countries, free, no IAP
- [ ] Privacy policy URL live
- [ ] Contact details + support e-mail (use GitHub issues or dedicated support inbox)

### Apple App Store

- [ ] Build uploaded via Xcode → Organizer or `flutter build ipa` + Transporter
- [ ] App name, subtitle, promo text, description, keywords filled, categories set
- [ ] App icon 1024 uploaded; screenshots for 6.7″, 6.5″, iPad 12.9″ uploaded
- [ ] App Privacy → Data Not Collected declared; privacy policy URL live
- [ ] Age rating 4+; review notes + demo account (none) provided
- [ ] Export compliance → no encryption beyond standard HTTPS (or declare accordingly)

---

## Contact & links

- **Support / issues:** https://github.com/crisperplayer/crisperplayer/issues
- **Privacy policy:** https://github.com/crisperplayer/crisperplayer/blob/master/PRIVACY.md (create if missing — see below)
- **Source:** https://github.com/crisperplayer/crisperplayer
- **Direct support e-mail (optional for Play):** add a monitored alias before production release (Play requires e-mail).

If `PRIVACY.md` does not yet exist, create a minimal policy stating: no network, no tracking, no analytics, no ads, all data stays on device, export is user-controlled JSON, deletion via app or uninstall.

