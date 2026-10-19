# CrisperPlayer privacy policy

Last updated: 19 October 2026.

CrisperPlayer plays audiobooks you choose and keeps its library, bookmarks,
listening history and settings on your device. There are no advertising,
tracking, analytics or crash-reporting services operated by CrisperPlayer.
There is no CrisperPlayer account or hosted sync backend.

## Optional connections and sync

Network access is used when you choose Plex, Filen, Internxt, Nextcloud,
WebDAV, SFTP or SMB for browsing and offline downloads. Those servers/providers
receive the authentication and file requests needed for their service and can
keep their own access logs. Their privacy policies apply to your accounts.
Filen and Internxt downloads are decrypted on your device through their SDKs.
CrisperPlayer does not upload your audiobooks as part of importing or sync.

Optional Plex progress sync sends track identifiers and listening positions to
your Plex server. The Plex server owner can read that information.

Optional folder progress sync uploads encrypted listening positions, track
content hashes/durations and synchronization counters to the folder you select
in Nextcloud/WebDAV, Filen or Internxt. AES-256-GCM protects the snapshot using
a shared passphrase derived with PBKDF2-HMAC-SHA256. The provider can see file
names, sizes and access times. It cannot read the snapshot without the shared
passphrase; anyone you give the passphrase to can read/write your progress.
There is no passphrase recovery service. See [sync behavior](docs/CLOUD_SYNC.md).

Credentials, provider session keys and sync passphrases are stored through the
platform's secure storage. Local builds on this Mac explicitly use the
Brickwright keychain. SDK configurations use temporary directories and
memory-backed credential stores rather than SDK home-directory credential files.
Temporary decrypted downloads are removed after completion or handled failure;
an abrupt system/process termination can leave disposable staging files until
OS cleanup. The app's persistent library and JSON metadata backups are not
separately encrypted by CrisperPlayer and rely on device/OS protection.

## Local data and exports

The app copies imported audio into its own storage and records titles, authors,
artwork, chapters, file paths, progress, bookmarks, notes, history and settings
in a local SQLite database and preferences. Originals remain unchanged.
Explicit exports contain metadata, not the audio; you choose where to save/share
them. Anyone with access to an unencrypted export can read its contents.

The browser player stores selected audio and progress in that browser's
IndexedDB. Audio is processed locally, without an upload endpoint. Its progress
backups contain metadata and sampled file fingerprints. GitHub hosts the public
Pages site and may log web requests; browser storage can be cleared or evicted.

## Platform features and permissions

- File selection/import uses the operating system's picker and selected files.
- Android requests media/file access as needed, notifications and foreground
  media playback permissions. Internet access supports optional servers/sync.
- iOS uses background audio and local-network access for servers you configure.
  Share intake and the optional iOS widget use a dedicated application group.
- Media controls expose the playing book's title/author/artwork to the operating
  system, lock screen, connected car/headset and media session.
- Android widgets store a small local title/author/play-state snapshot. The
  optional Watch companion sends commands and playback snapshots between your
  paired Apple devices using WatchConnectivity. Companions receive no cloud
  credentials. Their distribution/provisioning status is documented separately.
- The desktop CLI uses an authenticated loopback connection to the running app;
  its local descriptor contains an access token and should be kept private.

No microphone, camera, location, contacts or advertising-tracking permission
is requested for these features.

## Retention and deletion

You can delete books and managed copies, clear history/bookmarks and disconnect
servers in the app. Uninstalling normally removes local app storage; OS secure
storage and user-created exports can survive uninstall. Disabling sync keeps
local progress and existing remote snapshots. Delete the dedicated sync folder
through your provider to erase those remote files. Plex data is managed by your
Plex server. Original audio and your exports are never deleted by book removal.

## Contact

Christian Ströbele — [privacy questions](mailto:postmaster@crispstro.be).
Source and issue tracker: https://github.com/CrispStrobe/crisperplayer
