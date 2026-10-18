CrisperPlayer 0.1.0 build 14

- Editable elapsed time with keyboard entry, clock formats, range validation and touch stepping.
- Measured, cached current-track waveforms with local generation and scrubbing, replacing decorative animation.
- Playback volume sheet with percentage slider, mute/restore, 5% steps and persisted app volume.
- CLI clock-format seeks and waveform generation; browser time editing and mute/restore.
- Paused book loads now immediately publish the correct track, duration and position.
- Permanent release downloads: signed Android APK, complete Windows/Linux/Mac
  app bundles and CLI companions, including both Apple silicon and Intel Macs.
- New GitHub Pages local-file browser player with audio imports, multiple tracks,
  playback speed, resume, bookmarks, title search and metadata export.
- About dialog with installed version, provider/contact details, privacy information,
  source/download links and third-party/native-library licenses.
- GNU AGPL-3.0 project license, matching CrisperWeaver.
- Dedicated Android release signing key and complete-release checksum manifest.
- Fixed the isolated SMB source-change test on Linux's whole-second timestamps.

The native player includes local chapters, bookmarks, queue, series/collections,
per-book settings and offline Plex/WebDAV/SFTP/SMB downloads.

Windows binaries are unsigned; Mac downloads are ad-hoc signed and not notarized.
Linux builds target Ubuntu 24.04-compatible x64 systems and require system libmpv/GTK/libsecret.
iOS is delivered separately through internal TestFlight. Browser codec/background
support varies; embedded chapters and NAS access require the native app.
