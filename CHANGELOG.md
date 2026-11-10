# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- Added experimental **WSOLA** Android speed processing through a maintained
  portable Chromium BSD-3-Clause fork. The same streaming core supports host
  WAV comparisons. The extraction retains exact upstream sources, Git blob
  hashes, original notices and reproducible reference checks; it adds no
  Chromium browser runtime, mpv, or external GPL/AGPL dependency. Sonic remains
  the default and the selection applies after restart.

- Added final Android APK evidence checks for native hashes/dependencies,
  ABI and 16 KB alignment, loader-reachable JNI exports, retained DEX native
  declarations, exact pinned-NDK C++ runtime bytes and packaged notices.
  Debug, R8 release and actual signed release build paths prepare and verify
  the notices; the reports remain separate from release/license approval.
- Connected **Listening map → Playback dates** to the dated journal for an
  exact physical point or range. Real play-throughs and Return Trail replays
  remain separate; seeks and pauses are excluded. Lookup leaves playback
  unchanged, composes with date filters and preserves safe paused navigation.
- Added complete filtered **CSV and JSON journal reports**, with source and
  destination paths omitted by default, exact UTC/offset/position records,
  streamed encoding and spreadsheet formula protection. Reports are separate
  from restorable library backups. Book deletion now explicitly discloses the
  bookmarks and listening memory it removes.
- Selected Xcode 26.2 in Apple audio CI to satisfy the existing
  `device_info_plus` SDK requirement; macOS native algorithm tests already
  passed on the preceding checkpoint.
- Added experimental **Bungee Basic** and **Signalsmith Stretch** Android speed
  processors through a real Media3/JNI PCM pipeline. Sonic remains the default;
  processor changes apply after restart. Native modes preserve source timing,
  drain/reset buffered audio and retain saved skip-silence preferences while
  explaining that silence removal requires Sonic.
- Vendored the exact MPL/permissive DSP source closure and original notices,
  with an offline native build, streaming correctness tests, WAV comparison
  renderer and Android compile/JNI CI. No GPL/AGPL external processor was added.
- Corrected the distribution checker to honor the owner's confirmed authority
  and existing App Store permissions for CrisperPlayer and `crisp_storage`.
  External dependencies remain checked independently.
- Added an optional **Apple Spectral** speed processor alongside Time Domain on
  iOS/macOS, using a documented patch to the MIT-licensed just_audio adapter.
  Selection applies after restart and uses the AVFoundation system API.
- Added an external dependency policy excluding GPL-only and AGPL-only grants,
  exact dependency/native evidence checks, and release gates. Project-owned
  CrisperPlayer and `crisp_storage` are covered by the owner's confirmed
  distribution authority; their AGPL notices are preserved and do not block
  the policy. External dependency checks still apply to their complete graph.
- Added an optional **Listening journal** with persistent dated playback,
  separate replays, stops and explicit source/destination jumps; date and book
  filters; a year-ago shortcut; pagination; and paused historical navigation
  protected by a saved-place bookmark. Schema seven adds validated journal
  backups and stable checkpoint IDs without automatic expiry.
- Added exact speed entry and 0.05× adjustments, listening-time estimates and
  supported Windows/Linux Automatic versus Legacy scaletempo processing choices.
  Desktop processor changes apply on restart; platform-specific behavior is
  documented in [speed processing](docs/SPEED_PROCESSING.md).
- Made full metadata exports transactionally consistent and routed history
  clearing through the playback coordinator so pending writes cannot restore
  deleted history. See [journal behavior](docs/LISTENING_JOURNAL.md).
- Added **Listening map** with cumulative played sections, visible gaps, unique
  coverage percentages, per-track timelines and deliberate paused navigation.
  Schema six preserves coverage beyond the recent replay buffer and includes it
  in migration, history deletion, managed-file adoption and metadata backups.
- Added **Return Trail** in the native player and desktop CLI: inspect and replay
  short passages previously played on the device while protecting the normal
  resume point, then return paused or explicitly continue from the reviewed place.
- Added bounded local passage recording, schema-five migration and backup/restore
  support. Clearing listening history also clears recorded passages.
- Added regression coverage for protected progress, decoder failures, transition
  races, sleep timers, unknown durations, source gaps and accessible player controls.
- See [feature behavior](docs/RETURN_TRAIL.md),
  [validation and screenshots](docs/RETURN_TRAIL_VALIDATION.md), and the
  [product rationale](docs/design/RETURN_TRAIL.md).

## [0.1.0]

### Added
- **m4b chapter parsing & cover art** — parse chapter metadata from m4b files and display embedded cover artwork in the player and library
- **Sleep timer with End-of-Chapter (EoC)** — stop playback at the end of the current chapter, in addition to fixed-duration presets (15/30/60 min)
- **Smart rewind** — automatically rewind a configurable number of seconds when resuming playback after a pause, so you never lose your place
- **Onboarding flow** — first-launch experience introducing core features and guiding users to import their audiobooks
- **Library sorting** — sort library by date added, last played, title, author, or duration
- **48 unit and widget tests** covering chapter parsing, database, format utilities, playback logic, sleep timer, and UI widgets

## 0.1.0+18

- Reused the Filen macOS sandbox patch from CrispCloud, avoiding unsafe Homebrew OpenSSL loading; verified native AES-GCM round trips and rejection of modified ciphertext.

## 0.1.0+17

- Corrected companion embedding order before Flutter thinning, fixing the Watch host archive dependency cycle.

## 0.1.0+16

- Added upload QR pairing, mobile keep-awake behavior, on-device progress, resumable large-file chunks and duplicate-import protection.
- Corrected Filen root discovery and Internxt filename/download handling after live-account acceptance tests.

- Fixed Android release startup failure caused by R8 renaming or removing Kotlin coroutine types and runtime helpers used by SharedPreferences JNI; added an emulator startup gate for the release APK.

- Added foreground browser-to-device audiobook uploads with per-session access codes, streaming transfers and normal library import.

- Added Filen, Internxt and Nextcloud offline sources and secure SDK session refresh.
- Added opt-in Plex progress and encrypted provider-folder progress with conflict resolution and CLI parity.
- Added Android Auto browsing, an Android playback widget and native Apple companion integrations with explicit provisioning requirements.
- Prepared draft App Store metadata, corrected privacy documentation and added optional trusted desktop-signing automation.
- Included cloud SDK source/license notices in About and compiled CLI bundles.
