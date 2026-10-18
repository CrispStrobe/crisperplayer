# CrisperPlayer

A local audiobook player built with Flutter, Riverpod, Drift, just_audio and audio_service.

## Current scope

- Android and iOS playback, with notification/lock-screen controls and background audio.
- Desktop playback using the native macOS backend or media_kit on Linux/Windows.
- Imports copy selected audio into application storage; deleting a book removes its managed copies, not the source files.
- Multi-file books use natural filename order and measured per-track durations. Unknown durations remain unknown until the decoder provides them.
- Resume positions, bookmarks and listening history are stored locally. Bookmarks restore the book and physical track as well as the position.
- M4B/M4A Nero and QuickTime text-track chapters and embedded covers are parsed on device, including Unicode titles. Large audio payloads are skipped rather than loaded into memory. Existing imports can reload embedded chapters from the player menu or CLI.
- Player and system next/previous controls navigate chapters within a file and across files. Previous restarts the current chapter after three seconds. The player shows listening time remaining at the selected speed.
- Editable titles/authors/covers, series with numbered order, named collections, and finished/unfinished/unread status. Imports read MP4, ID3v2.3/v2.4, FLAC and Ogg Vorbis/Opus title/author/artwork tags. MP3 CHAP frames and Vorbis chapter tags are supported.
- Persistent Up next queue with reordering and automatic continuation at book completion. Sleep timers prevent automatic continuation.
- Per-book speed, skip silence, skip interval and smart rewind overrides; missing overrides inherit app defaults. Configurable volume, automatic bookmarks, startup restoration and theme. Decoder support for codecs and skip silence varies by platform.
- Sleep timers can pause immediately at expiry or at the end of the chapter playing when the countdown expires. Immediate chapter mode captures the current chapter boundary.
- Android voice boost (0–12 dB) and speech/warm/bass-reduction equalizer presets, with per-book overrides and graceful fallback when hardware effects are unavailable.
- Plex music-library albums and WebDAV/SFTP NAS folders download as offline books; files stream to disk and credentials stay in platform secure storage. Mounted shares can be imported as folders on desktop.
- JSON metadata export/import. Exports do not contain audio files; restoring on another device still requires accessible audio files.

Plex, WebDAV and SFTP connections support browsing and offline downloads. Cross-device progress sync is not implemented. The web build displays an availability notice; browser audio import, playback and persistent library storage are not supported in this version.

## Development

Use Flutter 3.44 or newer (Dart 3.12). The iOS deployment minimum is 15.0; Android uses the Flutter SDK minimum.

```sh
flutter pub get
dart run build_runner build --build-filter lib/services/db/app_database.g.dart
flutter analyze
flutter test
flutter run -d <device-id>
```

The database upgrades version-one and version-two libraries in place; schema three adds organization, playback preferences and the queue; schema four adds remote download identities without credentials. Legacy file references are adopted into app storage and their durations measured when first opened; unavailable source files must be re-imported.

The playback tests use the production coordinator and SQLite with an injected audio backend that preserves just_audio's pending `play()` future semantics. Native decoder, interruption and background behavior still require device testing:

```sh
flutter test integration_test/app_test.dart -d <device-id>
```

See [architecture](docs/ARCHITECTURE.md), [Android build](docs/ANDROID_BUILD.md), [iOS build](docs/IOS_BUILD.md), and [sync design](docs/CLOUD_SYNC.md).

## macOS and CLI

On this Mac, run the desktop app with the Brickwright signing and credential
keychain helper (see the local keychain section below):

```sh
python3 scripts/macos_local.py run
```

Desktop debug builds enable an authenticated loopback CLI. For a release build,
opt in with `--dart-define=CRISPERPLAYER_CLI=true`. The app must stay running:
the CLI controls its actual playback service and library.

```sh
dart run bin/crisperplayer.dart status
dart run bin/crisperplayer.dart import "/path/to/book.m4b"
dart run bin/crisperplayer.dart list
dart run bin/crisperplayer.dart play BOOK_ID
dart run bin/crisperplayer.dart pause
dart run bin/crisperplayer.dart seek 120
dart run bin/crisperplayer.dart speed 1.25
dart run bin/crisperplayer.dart bookmark "Start of chapter"
dart run bin/crisperplayer.dart bookmarks
dart run bin/crisperplayer.dart delete BOOK_ID
```

Commands return JSON; failures exit with code 1. `seek` uses seconds from the
start of the whole book. `import` streams files or recursively scanned folders
into the sandbox as one multi-track book, with natural filename order. It
creates managed copies and leaves source files untouched. `list.lastPositionMs` is the saved position within
the physical track; `status.positionMs` is the current position within the book.

The CLI exposes the GUI's library, playback, chapters, sleep timers, bookmarks,
history, settings, and metadata backup/restore operations. Use file paths and
JSON in place of file pickers and dialogs. `load BOOK_ID` opens a book paused.
Library search/filter/sort are available through `list --query`, `--filter`, and
`--sort`. `call COMMAND JSON_OBJECT` accepts structured arguments, including
bookmark notes. The desktop app continues to own audio and SQLite.

```sh
dart run bin/crisperplayer.dart import --title "My Book" --author "Author" "/path/to/tracks"
dart run bin/crisperplayer.dart chapters
dart run bin/crisperplayer.dart refresh-chapters
dart run bin/crisperplayer.dart next-chapter
dart run bin/crisperplayer.dart chapter 2
dart run bin/crisperplayer.dart sleep 900 --chapter-end
dart run bin/crisperplayer.dart settings themeMode dark
dart run bin/crisperplayer.dart bookmark-edit BOOKMARK_ID "New title" "Note"
dart run bin/crisperplayer.dart export library-backup.json
dart run bin/crisperplayer.dart restore library-backup.json
```

`clear-history` and `clear-bookmarks` require `--yes`. JSON backups contain
metadata and audio paths; audio files are not embedded in the backup.

Build a CLI executable with `dart build cli -o build/cli`, then run
`build/cli/bundle/bin/crisperplayer --help`. Keep the generated `bundle` folder
together when moving it. The CLI automatically finds the macOS connection file;
use `--control-file PATH` or `CRISPERPLAYER_CONTROL_FILE` to override discovery.
The connection file holds a per-run token and is private to the current user.

Run the native desktop integration test:

```sh
python3 scripts/macos_local.py test
```

It uses an isolated on-disk library and generated WAV audio, the real native
decoder, the UI, and the CLI endpoint. It checks duration, advancing playback,
pause, seek, speed, bookmarks, history, and persistence after reopening SQLite.
Audio is muted during the test. It does not establish audible output quality,
Bluetooth routing, or mobile interruption/background behavior.

## App icon

The source artwork is in `assets/branding/`. Run
`python3 scripts/generate_icons.py` with ImageMagick 7 installed to regenerate
the iOS, macOS, Android legacy/adaptive, Windows, Linux, and web icon assets.
iOS icons are opaque; macOS uses a rounded tile; adaptive and maskable icons
keep the emblem inside their mask's safe area.

## Feature priorities

The local audiobook experience is the first milestone. The reference apps are
[BookPlayer](https://github.com/TortugaPower/BookPlayer),
[Smart AudioBook Player](https://play.google.com/store/apps/details?id=ak.alizandro.smartaudiobookplayer),
and [Prologue](https://prologue.audio/). These are priorities, not a claim of complete parity.

| Priority | Work remaining |
| --- | --- |
| Added | MP4/ID3 title and author tags, MP3 artwork, editable book details/covers |
| Added | Per-book playback preferences and configurable smart rewind |
| Added | Series, collections, reading status and a persistent playback queue |
| Added | Player keyboard shortcuts and listening time totals (today/7 days/all time) |
| Added | FLAC/Vorbis/Opus tags, MP3 chapters, Android voice boost/EQ, Plex/WebDAV offline downloads |
| Added | Persistent partial downloads with pause/resume/discard, verified HTTP ranges, SFTP with pinned host keys |
| Added | Nested library-folder imports with book selection and numbered disc grouping; CLI dry run |
| Added | Player large-text layout, labeled touch targets, spoken seek values and reduced-motion waveform |
| Next | Wider accessibility/device audit and direct SMB |
| Later | Plex progress sync, CarPlay/Android Auto, widgets and Watch |
| Deferred | Optional local CrispASR transcripts and full-text search |

Every new player/library operation should be available through the desktop CLI.
Server integrations and platform extensions require their own device validation.

Book actions are available from the library's three-dot menu; player menus also
expose book details, playback preferences and Up next. Speed changes in the player
are remembered for that book. Application settings remain the defaults for books
without overrides.

```sh
dart run bin/crisperplayer.dart book-edit BOOK_ID '{"title":"Title","author":"Author","series":"Saga","seriesOrder":2,"collection":"Favorites"}'
dart run bin/crisperplayer.dart book-cover BOOK_ID /path/to/cover.jpg
dart run bin/crisperplayer.dart book-settings BOOK_ID '{"speed":1.5,"seekSeconds":15,"smartRewindSeconds":10}'
dart run bin/crisperplayer.dart book-settings BOOK_ID '{"speed":null}' # inherit default speed
dart run bin/crisperplayer.dart book-settings BOOK_ID reset
dart run bin/crisperplayer.dart mark BOOK_ID finished # or unfinished / unread
dart run bin/crisperplayer.dart list --series Saga --collection Favorites --sort series
dart run bin/crisperplayer.dart queue-add BOOK_ID 1 # position 1 plays next
dart run bin/crisperplayer.dart queue
dart run bin/crisperplayer.dart queue-remove BOOK_ID
dart run bin/crisperplayer.dart queue-play
dart run bin/crisperplayer.dart stats
```

In the player: Space toggles playback, arrows skip, Shift+arrows change chapter,
and B adds a bookmark. Shortcuts leave text editing alone. Listening statistics
show actual listening time, independent of playback speed.


The player and mini player support enlarged system text. Speed and sleep sheets
scroll on short screens. Screen readers announce elapsed/total seek times in
hours, minutes and seconds; increase/decrease actions use the configured skip
interval and stop at the book boundaries. Touch seeking stays continuous. The
waveform respects the system reduced-motion setting. These automated checks cover
player controls at 200% text and 320-pixel width; VoiceOver/TalkBack validation on
physical phones and a wider screen audit are still pending.

CI cancels superseded checks separately from binary jobs, so a newer push does
not interrupt Android or iOS simulator builds that have already passed checks.

## Plex and NAS libraries

Open **Import → Plex / WebDAV server** or **Settings → Servers & NAS**.
For Plex, enter the server URL and an [X-Plex-Token](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/).
Audiobooks must be in a music library, one album per book. Albums download all
tracks in disc/track order. For WebDAV, enter the NAS endpoint (including its
root path), username and password/app password. Open the folder containing a
book’s tracks and choose **Download folder as book**, or download a single file.
For SFTP, enter `sftp://hostname:22/books/`, a username and password. The first
connection shows the server’s SHA256 host-key fingerprint. Verify it with your
NAS and explicitly trust it; later connections require the pinned key. SFTP
browsing/downloads stay inside the configured root and omit symbolic links.
SSH private-key authentication is not implemented yet.
Downloaded books play offline and retain independent local progress.

HTTPS is the default. Private-IP and `.local` HTTP servers require explicit
opt-in. Invalid TLS certificates remain rejected. Requests do not follow
redirects or forward credentials to a different server or outside a WebDAV root.
Only download identities are in library backups; connection credentials stay in
Keychain/OS secure storage. Disconnecting leaves offline books intact.

CrispCloud’s separate provider adapters and secure credential storage informed
this design. The shared `crisp_storage` package in CrispCloud now supplies
Plex, WebDAV and SFTP transports, SSH trust, profiles and transfer scheduling;
direct SMB and automatic Plex progress synchronization are still pending.
Mount SMB shares with Finder/Explorer/the desktop file manager and use
**Import library folder / mounted share**. On iOS, connect a server in Files and select
audio through the file picker. **Import folder as one book** copies all selected folder audio, including subfolders,
as one book. **Import library folder / mounted share** scans nested author/book
folders and previews separate books before copying. Each directory containing
audio becomes a book; numbered `CD 1`, `Disc-2`, `Disk 3` and `Part_1` directories
join their parent book. Other nested audio folders remain separate books.
Review and deselect candidates before importing. Tracks use natural filename
order; hidden entries and symbolic links are skipped. You can stop between books;
completed imports remain in the library. Repeating an import creates new copies.
The CLI offers the same grouping, with a dry run that works without the app:

```sh
crisperplayer import-library "/Volumes/NAS/Audiobooks" --dry-run
crisperplayer import-library "/Volumes/NAS/Audiobooks"
```

A failed CLI batch exits with code 1 and reports completed book IDs and the failed
folder as JSON. Already imported books remain available; review this output before
retrying to avoid duplicates. WebDAV/SFTP folder downloads use direct audio
children only, in natural filename order. Large remote files temporarily require both download and managed
copy space. You can queue several books while browsing; downloads run one at a time.

Failed or paused transfers remain under **Downloads** in Servers &
NAS. Use Resume to continue, or Discard to remove their cached files. Partial
files survive app restarts; downloads are not automatically restarted in the
background. HTTP resume requires a strong ETag and a valid Range/If-Range
response; otherwise the transfer restarts safely. SFTP checks remote size and
modification time before resuming and after downloading. A book’s final import
must complete before it can be paused. Disconnecting a server leaves partial
jobs available to discard; resume requires the original connection.

The CLI provides the same remote operations. Read connection JSON from stdin to
keep secrets out of process arguments and shell history:

```sh
crisperplayer servers
crisperplayer call server-connect - < /private/path/connection.json
# connection JSON: {"name":"NAS","kind":"webdav","url":"https://nas.example/dav/","username":"reader","secret":"APP_PASSWORD"}
# Plex uses kind "plex", no username, and the Plex token in "secret".
crisperplayer call server-browse '{"connectionId":"ID","path":""}'
crisperplayer call server-download '{"connectionId":"ID","path":"RETURNED_PATH","title":"My book"}'
# Add "file": true for a single NAS file. An album/folder downloads as one book.
# Add "background": true to return immediately while the transfer runs.
crisperplayer server-downloads
crisperplayer server-cancel # pauses the active transfer, preserving its files
crisperplayer call server-resume '{"downloadId":"DOWNLOAD_ID"}'
crisperplayer call server-discard '{"downloadId":"DOWNLOAD_ID"}'
# SFTP connection JSON also uses "hostKey":"SHA256:...", obtained from your NAS.
# With no hostKey, connection fails and reports the fingerprint without authenticating.
crisperplayer call server-disconnect '{"connectionId":"ID"}'
crisperplayer settings boostDb 3
crisperplayer book-settings BOOK_ID '{"equalizer":"speech","boostDb":6}'
```

Native desktop integration also tests the connection dialog, Keychain storage,
WebDAV HTTP download and duration measurement of downloaded audio. Protocol
fixtures do not replace testing against your Plex/NAS installation.


Run isolated HTTP-resume and SFTP protocol tests (no NAS or OS account required):

```sh
python3 -m venv /tmp/crisper-protocol-tests
/tmp/crisper-protocol-tests/bin/pip install paramiko
CRISPER_SFTP_PYTHON=/tmp/crisper-protocol-tests/bin/python flutter test
```

CI runs the same SFTP fixture. It verifies host-key rejection before password
authentication, root confinement, ordered tracks, partial-file resume and offline
import. HTTP fixtures cover changed validators, malformed ranges, restarts,
cache cleanup, concurrent credential writes and out-of-band CLI cancellation.

The shared package is pinned to an exact CrispCloud Git commit in pubspec.yaml;
a fresh checkout and CI resolve it without a sibling repository. To develop the
package locally, use an untracked pubspec_overrides.yaml path override. Shared
package tests run in CrispCloud CI, while CrisperPlayer retains audiobook import,
resume, queue, GUI and native playback coverage.


### Local macOS keychain

On this Mac, use the dedicated Brickwright keychain for local signing and server
credentials:

```sh
python3 scripts/macos_local.py build
python3 scripts/macos_local.py run
python3 scripts/macos_local.py test
python3 scripts/macos_local.py test --test-file integration_test/named_keychain_test.dart
```

The helper selects the existing Apple Distribution identity from
`~/Library/Keychains/brickwright-build.keychain-db` and passes that keychain
explicitly to signing. It embeds `CRISPERPLAYER_MACOS_KEYCHAIN` in the local
build, so reopening that app continues to use the selected keychain.
`--keychain /absolute/path` selects another explicit keychain.

Credential reads, writes and deletes use only CrisperPlayer's own generic
password service in that keychain. Missing, locked or inaccessible selected
keychains fail without searching the login keychain. Existing credentials are
not moved automatically. The helper does not change the system keychain search
list or default, export private keys, or create signing identities. Ordinary
builds without this local override retain platform secure storage.
