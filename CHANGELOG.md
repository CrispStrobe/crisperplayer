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
