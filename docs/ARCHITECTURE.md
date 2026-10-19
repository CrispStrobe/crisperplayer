# Architecture

Flutter renders the UI; Riverpod owns service lifetimes and exposes Drift queries and observable settings. Drift is the local source of truth. Remote adapters authenticate to Plex, Filen, Internxt, Nextcloud, WebDAV, SFTP and SMB for offline imports. Optional Plex progress and encrypted folder progress use dedicated services; see [Cloud sync](CLOUD_SYNC.md).

## Playback

`PlaybackService` serializes UI, lifecycle and native media commands. Its `AudioBackend` boundary has a just_audio implementation and a deterministic test implementation. A single native `AudioPlayer` is shared with `CrisperAudioHandler`, which publishes media metadata and delegates controls to the coordinator.

The application awaits playback initialization before rendering. Windows/Linux register media_kit before creating any players. Android's activity extends `AudioServiceActivity` so background playback uses the same Flutter engine. Native initialization failures surface as startup errors.

`play()` requests playback without awaiting the long-lived just_audio playback future. Ready/playing events open a listening session; pauses, buffering and completion close it. Sessions use a monotonic stopwatch and checkpoint into SQLite every two seconds. Backgrounding checkpoints without ending an ongoing session. Book changes save and close the old session before replacing its queue.

A physical track and an embedded chapter are distinct concepts. `book_tracks` stores ordered file paths and nullable measured durations. Whole-book seeks and skips use those durations; file bookmarks retain their book, file and local offset. No equal-duration estimates or fabricated 30-minute tracks are used. Unknown durations prevent whole-book seeks past the unknown segment until timing is available.

Chapter-end sleep captures a fixed endpoint when entering chapter mode. Subsequent position and index events compare against that endpoint, including ticks that cross directly into the next chapter. The countdown and production pause path are shared with tests.

## Storage and imports

Library imports validate source availability, naturally sort filenames, stream-copy files into `<application-support>/library/<book-id>/`, probe durations and write books, tracks and chapters in a transaction. Import failure removes the managed copies. Deletion stops the active book, removes related metadata atomically and deletes only that book's managed directory.

Schema version two adds `book_tracks`; schema three adds series/collection fields, validated per-book playback overrides, manual reading-status overrides and `playback_queue`. Schema four adds `remote_links` for imported-book identities and duplicate detection, without credentials. Earlier rows and positions remain intact. The first load adopts legacy files into managed storage, remaps chapter/bookmark/resume paths and probes timing. Missing legacy files produce an actionable error instead of silently replacing their timing.

MP4 metadata extraction seeks past audio payload atoms and reads only the `moov` atom, with a 32 MB limit. Covers live alongside their managed book files. Nero and referenced QuickTime text-track chapters are supported. QuickTime sample tables and text reads are bounded, with stco/co64 offsets, Unicode titles and common edit-list timing. ID3v2.3/v2.4 text, artwork and CHAP reads are capped at 16 MB of tag data. FLAC metadata and Ogg Vorbis/Opus comment packets are bounded at 16 MB, with page/packet/count caps and cross-page reassembly. Vorbis chapter tags get measured final endpoints.

Metadata exports include schema version, tracks, organization, per-book preferences and queue order. Imports reject unsupported versions and apply updates atomically using upserts, avoiding SQLite REPLACE's delete-and-cascade behavior. Audio is not embedded in JSON.

## Settings and shares

`SettingsService` is a ChangeNotifier backed by SharedPreferences. Riverpod observes it for theme and settings UI; playback observes it for player configuration, seek intervals and automatic bookmarks. Startup restoration loads the last played book paused when enabled. Per-book speed, skip silence, seek interval and smart rewind inherit these defaults unless explicitly overridden. Player speed changes update the current book override.

The coordinator advances the persistent book queue only on playing completion and without a pending sleep timer. Failed loads retain their queue entry; successful loads remove it. The player follows CLI and queue book changes without reloading or pausing the new book.

Share intake accepts cold and warm shares, supports callback rebinding and serializes imports. Identical simultaneous deliveries share one import. The native stream and reset operations are injectable for regression tests.

## Platform scope

Installed Android, iOS and desktop apps use local filesystem storage. The browser build displays an explicit availability notice before initializing native storage or playback. It is not a browser player. Cloud sync is unavailable; `CLOUD_SYNC.md` records design requirements for a future authenticated implementation.


## Remote libraries and effects

`RemoteLibraryService` is shared by GUI and desktop control. `RemoteClient`
implements read-only Plex JSON and WebDAV PROPFIND/GET. Plex listings paginate;
WebDAV uses a namespace-aware XML parser and successful propstat values. Media
URLs must remain in the connection origin/root; credentials use headers and
redirects are rejected. Listing bodies have a 16 MB cap, downloads a 64 GB cap,
with connection and stalled-stream timeouts. Downloads stream to durable per-job directories under application support,
then use the normal managed import path. Pauses/failures retain cached audio
and validators; failed imports remove partial managed books. Successful imports
remove cached transfer files. Explicit discard removes a paused job. Download identities survive connection removal and
metadata backup/restore, and book deletion cascades their removal.

Connection configurations are stored together in platform secure storage,
never SharedPreferences or SQLite. macOS uses the login Keychain to support
locally signed desktop builds; iOS uses the app’s Keychain access group and
first-unlock accessibility. HTTP requires explicit opt-in for private/link-local/
loopback IPs or `.local` hostnames; all other connections require HTTPS.

Android’s engine-owned `AudioEffectsPlugin` attaches Equalizer/LoudnessEnhancer
to just_audio’s audio session, releases on session change or engine disposal,
and reports unsupported effects without failing playback. Defaults leave native
effects uninstantiated. Settings and per-book overrides share validated gain
and preset values; non-Android platforms show the feature as unavailable.


Transfer manifests contain connection IDs and item paths, without passwords or
tokens. HTTP sidecars bind a strong ETag to a source URL; Range/If-Range and
Content-Range checks prevent appending a replacement object to old bytes.
Ignored ranges restart the file, and an unchanged complete object can be reused
via a validated 416 response. Encoded responses are rejected. Servers lacking
strong validators restart. SFTP uses size/mtime validation and offset reads.

SFTP uses dartssh2 with explicit SHA256 host-key pinning before password
authentication. The first connection reports a fingerprint and requires explicit
trust in the dialog or a known hostKey in CLI connection JSON. Canonical paths
must remain within the configured root; folder listings omit symlinks. The
connection dialog owns its text controllers until its route is removed, and
fields are disabled during connection so the displayed address and offered host
key cannot diverge.

GUI and CLI share persistent jobs. The CLI supports immediate background starts;
blocking downloads remain cancellable through a separately authenticated,
allowlisted `/transfers` endpoint for pause/status only. Normal mutations remain
serialized. Credential writes are serialized separately to prevent concurrent
GUI/CLI sign-ins from losing stored accounts. Offline playback and listening
progress remain independent of remote transfer state.


## Distribution and browser player

Tagged builds use `release.yml` and `scripts/release.py` to create complete app and
native-asset CLI archives for Windows, Linux and both Mac architectures, plus a
persistently signed Android APK. The release stays a draft until all required
platforms succeed; an exact tag/pubspec match and checksums guard publication.
iOS App Store delivery/internal TestFlight uses its own existing workflow.

`site/` is a separate static browser player, deployed to GitHub Pages. It uses
HTMLAudioElement, browser codecs and IndexedDB, with no Flutter/native transports,
SQLite, server credentials or synchronization. Audio blobs and metadata are stored
atomically, book progress is saved independently, and imported names are rendered
as text. Browser tests use generated audio and the production Pages project path.

The shared CrispCloud `crisp_storage` package now includes direct SMB2/3 in addition
to Plex/WebDAV/SFTP. SMB3 encryption is required unless explicitly disabled for a
signed SMB2 connection. Both apps use the same shared transport and resume checks.


## Progress and companion surfaces

`PlexProgressService` uses a durable three-way baseline against original album
track IDs. `FolderProgressService` matches ordered audio SHA-256 hashes and
stores AES-GCM-encrypted per-device snapshots in a configured provider folder.
`ProgressRecord` implements vector-clock comparison and explicit conflict
resolution. Neither service applies an incoming seek to an open book. Credentials
and folder passphrases use the same platform credential store as server profiles.
See [sync semantics and limits](CLOUD_SYNC.md).

`MediaLibrary` provides the bounded local browse tree for `CrisperAudioHandler`
and native CarPlay. `CompanionService` routes widget/Watch commands through the
same PlaybackService coordinator. Native companions receive playback snapshots,
not database handles, cloud credentials or a second audio engine. See
[companion provisioning and validation](COMPANIONS.md).
