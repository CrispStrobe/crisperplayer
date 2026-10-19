# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0]

### Added
- **m4b chapter parsing & cover art** — parse chapter metadata from m4b files and display embedded cover artwork in the player and library
- **Sleep timer with End-of-Chapter (EoC)** — stop playback at the end of the current chapter, in addition to fixed-duration presets (15/30/60 min)
- **Smart rewind** — automatically rewind a configurable number of seconds when resuming playback after a pause, so you never lose your place
- **Onboarding flow** — first-launch experience introducing core features and guiding users to import their audiobooks
- **Library sorting** — sort library by date added, last played, title, author, or duration
- **48 unit and widget tests** covering chapter parsing, database, format utilities, playback logic, sleep timer, and UI widgets

## 0.1.0+16

- Added foreground browser-to-device audiobook uploads with per-session access codes, streaming transfers and normal library import.

- Added Filen, Internxt and Nextcloud offline sources and secure SDK session refresh.
- Added opt-in Plex progress and encrypted provider-folder progress with conflict resolution and CLI parity.
- Added Android Auto browsing, an Android playback widget and native Apple companion integrations with explicit provisioning requirements.
- Prepared draft App Store metadata, corrected privacy documentation and added optional trusted desktop-signing automation.
- Included cloud SDK source/license notices in About and compiled CLI bundles.
