CrisperPlayer 0.1.0 build 18

- Reused CrispCloud’s Filen macOS sandbox compatibility patch; native encryption/decryption and authentication rejection were verified in the Brickwright-signed Mac app.
- Corrected Apple companion embedding order to avoid a Watch archive dependency cycle. The iOS widget remains deferred.
- Fixed Android startup crash in the release APK; release publication now requires an emulator startup and reinstall check.
- Browser-to-device audiobook uploads over trusted Wi-Fi with QR pairing, access codes, on-device progress, mobile keep-awake and resumable large-file chunks; foreground only.
- Filen, Internxt and Nextcloud join Plex/WebDAV/SFTP/SMB offline libraries, using the SDKs shared with CrispCloud. Cloud credentials and refreshed sessions remain in secure storage. Local live-account tests verified Filen and Internxt import, encrypted progress and conflict resolution, plus Internxt session renewal. Nextcloud live-account testing remains pending.
- Optional Plex listening-position sync with persistent offline baselines, explicit conflicts and protection for open books.
- Encrypted progress sync through your own Nextcloud/WebDAV, Filen or Internxt folder. Content hashes match tracks across devices; vector clocks preserve concurrent edits for a choice. No audio uploads.
- Android Auto library/queue/chapter browsing and voice search; Android home-screen playback widget.
- Shared native commands for CarPlay, iOS widget and Watch remote controls. Apple companion distribution remains gated by its entitlement/profiles; independent builds validate the sources. Watch controls the iPhone, without standalone audio playback.
- Desktop CLI parity for both sync modes and every cloud connection; package/SDK license notices updated.
- Release automation supports verified Developer ID/notarization and Windows Authenticode when the required certificates are configured. Without those credentials, Windows downloads remain unsigned and Mac downloads ad-hoc signed/not notarized.

For folder progress sync use the same existing provider folder and 12+ character
passphrase on each device, with unchanged copies of the same audio. The first
fingerprint pass can take time. Unknown track durations need playback probing.
Plex libraries need Store track progress enabled. Incoming positions apply only
to closed books or through an explicit action that reloads them paused.

Test local/offline and concurrent-device positions, cloud imports, car/widget
commands, timers, interruptions and background playback on real devices.
iOS is delivered separately through internal TestFlight; public App Store
metadata is prepared without submitting review or releasing the app publicly.
