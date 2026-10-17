# Privacy Policy — CrisperPlayer

> Effective date: 2026-10-17 • Version 0.1.0 • Contact: https://github.com/crisperplayer/crisperplayer/issues

CrisperPlayer is an **offline-first audiobook player**. This policy explains what data the app accesses and what it does not.

## Summary

- **No network access.** The production app does not make network requests, does not contact a server, and does not use analytics, crash reporting, advertising SDKs, or tracking.
- **No data collection.** We do not collect, transmit, or share personal information. All data stays on your device.
- **No accounts.** No sign-in, no cloud sync in v0.1.

## Data stored on your device

When you import audiobooks via the system file picker, the app stores locally (SQLite via Drift + SharedPreferences):

- Book metadata you import (title, author, file paths, duration, cover art cache)
- Playback state (last position, progress)
- Chapters parsed from m4b files (on-device)
- Bookmarks (manual and automatic) and listening history (start/end timestamps)
- Settings (playback speed, skip silence, theme, sleep timer preferences)

This data never leaves your device except through **Export** you initiate (see below).

## Permissions

### Android

- **READ_MEDIA_AUDIO / READ_EXTERNAL_STORAGE (≤ Android 12):** to read audiobook files *you select* via the file picker. The app does not scan storage without user action.
- **POST_NOTIFICATIONS:** to show playback controls in the notification shade and lock screen.
- **FOREGROUND_SERVICE + FOREGROUND_SERVICE_MEDIA_PLAYBACK:** to continue playback with the screen off.
- **WAKE_LOCK:** to prevent the device from sleeping during playback.

`INTERNET` is declared only in debug/profile builds for Flutter tooling; the release app declares no network permission.

### iOS

- **Background Audio (`UIBackgroundModes = audio`):** to play with the screen locked and in Control Center.
- **Apple Music usage description:** displayed if the system requests media-library access for lock-screen metadata; no library browsing is performed.

No photo library, microphone, camera, location, contacts, or tracking permissions are requested.

## Export / Import

Settings → Export creates a JSON file on your device containing your library index, bookmarks, and history. You choose where to save or share it. Import reads a JSON file you select. No data is sent to us.

## Data retention and deletion

- All data is retained until you delete it in-app (delete book, clear history/bookmarks, reset settings) or uninstall the app.
- Uninstalling removes the app's database and preferences from device storage.

## Children

The app does not target children under 13 and does not knowingly collect data from children. It is rated Everyone (Play) / 4+ (App Store).

## Third-party services

None in v0.1. No analytics, crash reporters, ads, or external SDKs that collect data.

## Changes

Material changes will be noted in `CHANGELOG.md` and this file. Continued use after an update constitutes acceptance.

## Contact

For questions or data-deletion requests, open an issue at https://github.com/crisperplayer/crisperplayer/issues or use the support e-mail listed in the store listing.

