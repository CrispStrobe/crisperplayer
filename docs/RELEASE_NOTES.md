CrisperPlayer 0.1.0 build 15

- Custom sleep timers from 1 to 1440 minutes, with keyboard entry and remembered custom duration.
- Quick +5/+15-minute extensions preserve chapter-end mode, including when already waiting for a chapter boundary.
- Sleep timers use a deadline instead of counting callbacks and check overdue timers when returning to the foreground.
- CLI `sleep extend SECONDS` shares the same timer and chapter behavior as the app.
- Fixed an automatic-bookmark timer that could remain active during shutdown if a settings command was still pending.
- Complete signed Android APK and Windows/Linux/Mac app and CLI downloads, with SHA-256 checksums; Windows builds use Visual Studio 2022 for plugin compatibility.

The native player includes local chapters, bookmarks, queue, series/collections,
per-book settings and offline Plex/WebDAV/SFTP/SMB downloads.

Windows binaries are unsigned; Mac downloads are ad-hoc signed and not notarized.
Linux builds target Ubuntu 24.04-compatible x64 systems and require system libmpv/GTK/libsecret.
iOS is delivered separately through internal TestFlight. Browser codec/background
support varies; embedded chapters and NAS access require the native app.
