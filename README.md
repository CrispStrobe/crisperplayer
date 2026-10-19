# CrisperPlayer

A local-first audiobook player for Android, iOS, macOS, Windows and Linux.
Keep your place, organize your books, and download from Plex, Filen, Internxt, Nextcloud or your NAS for offline listening.

[**Download the native apps and CLI**](https://github.com/CrispStrobe/crisperplayer/releases/latest) · [**Listen in your browser**](https://crispstrobe.github.io/crisperplayer/) · [Installation and release automation](docs/RELEASES.md)

| Platform | Distribution |
| --- | --- |
| Android | [Signed APK](https://github.com/CrispStrobe/crisperplayer/releases/latest/download/CrisperPlayer-android.apk) |
| Windows x64 | [Complete ZIP bundle](https://github.com/CrispStrobe/crisperplayer/releases/latest/download/CrisperPlayer-windows-x64.zip) |
| macOS Apple silicon | [App + CLI ZIP](https://github.com/CrispStrobe/crisperplayer/releases/latest/download/CrisperPlayer-macos-arm64.zip) |
| macOS Intel | [App + CLI ZIP](https://github.com/CrispStrobe/crisperplayer/releases/latest/download/CrisperPlayer-macos-x64.zip) |
| Linux x64 | [App + CLI archive](https://github.com/CrispStrobe/crisperplayer/releases/latest/download/CrisperPlayer-linux-x64.tar.gz) |
| iOS 15+ | Internal TestFlight; team access required |
| Browser | [GitHub Pages local-file player](https://crispstrobe.github.io/crisperplayer/) |

Extract desktop archives completely before launching; keep their libraries and data together.
Windows builds are unsigned and Mac downloads are ad-hoc signed, not notarized.
Windows needs the Microsoft Visual C++ runtime (x64); Linux needs system libmpv, GTK and libsecret. See [installation details](docs/RELEASES.md).
Release checksums and separate CLI bundles are attached to each versioned GitHub release.

## Send books from a computer

In the installed app choose **Add books → Upload from browser**. Start sharing,
open the displayed address on a computer on the same trusted Wi-Fi network,
and paste the access code. Select all tracks for one book to upload and import
with progress. Keep the app open and the device unlocked; sharing stops when
you leave the screen or background the app. HTTP transfers are not encrypted.
See [limits, permissions and platform behavior](docs/BROWSER_UPLOADS.md).

## Browser player

The Pages site plays audio files selected from your device and stores audio, progress,
speed, volume and bookmarks in IndexedDB. Select one file or all tracks of one book;
tracks use natural filename order. It supports search, track navigation, editable/deletable
bookmarks, and JSON progress backup/restore. Restore checks the selected audio, shows a
preview, and keeps existing bookmarks without duplicating restored entries. Audio stays
in your browser; there are no analytics or audio uploads.

Browser codec support varies. Embedded M4B chapters, NAS connections, the full native
library and native-library JSON restore require the installed app. Background playback
depends on the browser and operating system.
Clearing site data removes the browser library; keep your original audio.
For a browser restore, add the original audio files, select that book, and choose
**Restore progress**. Review the matching tracks and saved position before confirming.
See [browser backups and format details](docs/WEB_PLAYER.md).
This is a separate static player in `site/`, deployed by `pages.yml`; `flutter build web`
currently builds the native app's platform-availability notice.

## About and licenses

Open **Settings → About CrisperPlayer** for the installed version/build, provider and
contact information, privacy details, source/download links, and third-party licenses.
The license screen includes Flutter package notices and native SQLite, libsmb2 and
desktop audio notices. Native notice texts are also included in release archives and
[assets/licenses](assets/licenses). CrisperPlayer is licensed under [GNU AGPL-3.0](LICENSE), © 2026 Christian Ströbele.
Third-party components retain their upstream licenses.

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
- Sleep timers support custom 1–1440-minute durations, remembered custom duration, and +5/+15-minute extensions. They pause immediately at expiry or at the end of the chapter playing when the countdown expires. Deadline-based countdowns catch up after delayed callbacks or returning to the foreground. Immediate chapter mode captures the current chapter boundary.
- Android voice boost (0–12 dB) and speech/warm/bass-reduction equalizer presets, with per-book overrides and graceful fallback when hardware effects are unavailable.
- Plex music-library albums and WebDAV/SFTP/SMB NAS folders download as offline books; files stream to disk and credentials stay in platform secure storage. Mounted shares can be imported as folders on desktop.
- JSON metadata export/import. Exports do not contain audio files; restoring on another device still requires accessible audio files.

Plex, Filen, Internxt, Nextcloud, WebDAV, SFTP and SMB support browsing and offline downloads. Optional [progress sync](docs/CLOUD_SYNC.md) supports Plex and encrypted files in your own cloud folder. The Pages browser player has the smaller local-file scope described above.

## Playback controls

Tap/click the elapsed time to jump to an exact book position. Enter `HH:MM:SS`,
`MM:SS` or seconds (including milliseconds), then press Enter or **Jump**.
The dialog also has touch buttons to adjust the target by 30 seconds; Cancel
leaves playback untouched. When whole-book durations are unavailable, this
control explicitly targets the current track.

The volume button beside the time opens a percentage slider, 5% adjustment
buttons and mute/unmute that restores the previous level. It controls the app's
gain; hardware/device volume is separate. Volume is saved across launches.

The decorative animation is replaced with **Audio waveform · current track**.
Choose **Generate audio waveform** to analyze that track locally, then tap/drag
the measured waveform to seek within it. Silence stays flat; playback only moves
the playhead and tint. Generation is explicit because long tracks may take time.
Results are cached by file identity; changing the audio invalidates its cache.
Use the eye button to hide/show the waveform. PCM WAV analysis works on every
native platform. Android/iOS/macOS decode compressed audio natively; Windows/Linux
also need an installed `ffmpeg` executable on PATH for compressed-file waveforms.
Playback remains available if analysis is unsupported or fails. No audio is uploaded.

The desktop CLI shares these operations:

```sh
crisperplayer seek 01:23:45.500
crisperplayer volume 0.65
crisperplayer mute
crisperplayer unmute
crisperplayer waveform # JSON measured peaks for the current track; may take time
crisperplayer settings showWaveform false
crisperplayer sleep 1020 --chapter-end # 17 minutes, then finish the chapter
crisperplayer sleep extend 300        # add five minutes, preserving chapter mode
```

Waveform analysis runs separately from the CLI playback command queue, so another
CLI invocation can still pause/seek/change volume while it is generating. The
Pages player also has editable track timecodes and a mute/restore volume control.

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
the CLI controls its actual playback service and library. Build the CLI with
`dart build cli -o build/cli`, then run
`python3 scripts/package_cli_notices.py build/cli/bundle`.

```sh
build/cli/bundle/bin/crisperplayer status
build/cli/bundle/bin/crisperplayer import "/path/to/book.m4b"
build/cli/bundle/bin/crisperplayer list
build/cli/bundle/bin/crisperplayer play BOOK_ID
build/cli/bundle/bin/crisperplayer pause
build/cli/bundle/bin/crisperplayer seek 120
build/cli/bundle/bin/crisperplayer speed 1.25
build/cli/bundle/bin/crisperplayer bookmark "Start of chapter"
build/cli/bundle/bin/crisperplayer bookmarks
build/cli/bundle/bin/crisperplayer delete BOOK_ID
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
build/cli/bundle/bin/crisperplayer import --title "My Book" --author "Author" "/path/to/tracks"
build/cli/bundle/bin/crisperplayer chapters
build/cli/bundle/bin/crisperplayer refresh-chapters
build/cli/bundle/bin/crisperplayer next-chapter
build/cli/bundle/bin/crisperplayer chapter 2
build/cli/bundle/bin/crisperplayer sleep 900 --chapter-end
build/cli/bundle/bin/crisperplayer settings themeMode dark
build/cli/bundle/bin/crisperplayer bookmark-edit BOOKMARK_ID "New title" "Note"
build/cli/bundle/bin/crisperplayer export library-backup.json
build/cli/bundle/bin/crisperplayer restore library-backup.json
```

`clear-history` and `clear-bookmarks` require `--yes`. JSON backups contain
metadata and audio paths; audio files are not embedded in the backup.

Run `build/cli/bundle/bin/crisperplayer --help` for all commands. Keep the generated `bundle` folder
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
| Added | Saved automatic/grid/list library layouts, responsive search/filter controls and accessible book actions |
| Added | Direct SMB2/3 NAS browsing, signed connections, optional required encryption and resumable offline downloads |
| Added | Custom sleep durations, quick timer extensions, deadline-based expiry and CLI timer parity |
| Added | Browser progress backup/restore with audio checks, bookmark merging, editing and deletion |
| Next | Wider accessibility/device audit |
| Added | Optional Plex progress sync and encrypted Nextcloud/WebDAV/Filen/Internxt progress files, with conflict resolution and CLI parity |
| Added | Android Auto browse tree and Android home-screen playback widget |
| Provisioning / device validation | CarPlay, iOS widget and Watch remote controls; [requirements and scope](docs/COMPANIONS.md) |
| Deferred | Optional local CrispASR transcripts and full-text search |

Every new player/library operation should be available through the desktop CLI.
Server integrations and platform extensions require their own device validation.

Book actions are available from the library's three-dot menu; player menus also
expose book details, playback preferences and Up next. Speed changes in the player
are remembered for that book. Application settings remain the defaults for books
without overrides.

```sh
build/cli/bundle/bin/crisperplayer book-edit BOOK_ID '{"title":"Title","author":"Author","series":"Saga","seriesOrder":2,"collection":"Favorites"}'
build/cli/bundle/bin/crisperplayer book-cover BOOK_ID /path/to/cover.jpg
build/cli/bundle/bin/crisperplayer book-settings BOOK_ID '{"speed":1.5,"seekSeconds":15,"smartRewindSeconds":10}'
build/cli/bundle/bin/crisperplayer book-settings BOOK_ID '{"speed":null}' # inherit default speed
build/cli/bundle/bin/crisperplayer book-settings BOOK_ID reset
build/cli/bundle/bin/crisperplayer mark BOOK_ID finished # or unfinished / unread
build/cli/bundle/bin/crisperplayer list --series Saga --collection Favorites --sort series
build/cli/bundle/bin/crisperplayer queue-add BOOK_ID 1 # position 1 plays next
build/cli/bundle/bin/crisperplayer queue
build/cli/bundle/bin/crisperplayer queue-remove BOOK_ID
build/cli/bundle/bin/crisperplayer queue-play
build/cli/bundle/bin/crisperplayer stats
```

In the player: Space toggles playback, arrows skip, Shift+arrows change chapter,
and B adds a bookmark. Shortcuts leave text editing alone. Listening statistics
show actual listening time, independent of playback speed.


Use the library’s **Library layout** menu to choose **Automatic**, **Cover grid**,
or **List**. The choice is saved between launches. Automatic uses a list with
enlarged system text; a manually selected grid scales its cards and text. Library
search, status, sort, collection and series controls scroll with the books on
small screens. The mini player stays pinned below the browser, with the Import
button above it. List rows include author, series, duration and reading progress.
The CLI reads and sets the same preference:

```sh
crisperplayer settings libraryView list # auto / grid / list
```

The player and mini player support enlarged system text. Speed and sleep sheets
scroll on short screens. Screen readers announce elapsed/total seek times in
hours, minutes and seconds; increase/decrease actions use the configured skip
interval and stop at the book boundaries. Touch seeking stays continuous. Measured waveforms do not animate their amplitudes, including when Reduce Motion is off. These automated checks cover
player controls at 200% text and 320-pixel width; VoiceOver/TalkBack validation on
physical phones and a wider screen audit are still pending.

CI skips documentation-only pushes. Code checks cancel superseded checks separately
from binary jobs, so a newer code push does not interrupt Android or iOS simulator
builds that have already passed checks. Tagged releases always run their full checks.

## Plex and NAS libraries

Open **Import → Server / NAS** or **Settings → Servers & NAS**.
Filen and Internxt use email/password and an optional two-factor code; their encrypted
files are decrypted locally using the SDKs shared with CrispCloud. Nextcloud accepts
your account base URL, username and app password. An interrupted encrypted file
restarts; completed tracks are reused only after metadata/size/SHA-256 checks.
Internxt pause takes effect after its current SDK transfer completes.
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
Plex, WebDAV, SFTP and SMB transports, SSH trust, profiles and transfer scheduling.
Optional [Plex and encrypted folder progress sync](docs/CLOUD_SYNC.md) are available. [Car interfaces and companions](docs/COMPANIONS.md) have separate provisioning/device requirements.
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
retrying to avoid duplicates. WebDAV/SFTP/SMB folder downloads use direct audio
children only, in natural filename order. Large remote files temporarily require both download and managed
copy space. You can queue several books while browsing; downloads run one at a time.

Failed or paused transfers remain under **Downloads** in Servers &
NAS. Use Resume to continue, or Discard to remove their cached files. Partial
files survive app restarts; downloads are not automatically restarted in the
background. HTTP resume requires a strong ETag and a valid Range/If-Range
response; otherwise the transfer restarts safely. SFTP and SMB check remote size and
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
# SMB: "kind":"smb", "url":"smb://nas.local/Audiobooks/", "username":"reader".
# SMB requires encryption by default; "requireEncryption":false permits signed SMB2 on a trusted LAN.
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
/tmp/crisper-protocol-tests/bin/pip install paramiko impacket
CRISPER_SFTP_PYTHON=/tmp/crisper-protocol-tests/bin/python \
CRISPER_SMB_PYTHON=/tmp/crisper-protocol-tests/bin/python flutter test
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

SMB connects directly to `smb://host/share/` (an optional subfolder is supported).
SMB3 encryption is required by default; older NAS servers can use signed SMB2
by explicitly turning that setting off. Domain accounts use `DOMAIN\user`.
SMB1 and browser connections are unsupported. Files are downloaded into the local
library before playback; optional Plex and encrypted folder progress sync are documented in [Cloud sync](docs/CLOUD_SYNC.md).

Run the isolated signed SMB2 transport suite with
`CRISPER_SMB_PYTHON=/path/to/python-with-impacket flutter test test/smb_live_test.dart`.
The tests verify rejected encryption downgrades, authentication, resume, changed
source detection, encoded names and file operations without using an OS share.

To include the native SMB connection, Brickwright credential and offline-playback
smoke test, use `python3 scripts/macos_smb_smoke.py --python /path/to/python-with-impacket`.
It starts a temporary loopback server and deletes its files and test credential
entry afterwards. No OS file share or NAS configuration is changed.


## Release and website maintenance

CI runs analysis, unit/protocol checks and binary smoke builds. Tagged releases additionally
build complete desktop app/CLI bundles on Windows, Linux and both Mac architectures,
plus the signed Android APK. Publication waits for every required platform and produces
`SHA256SUMS.txt`. iOS uses the separate signed internal TestFlight pipeline.
See [the release procedure](docs/RELEASES.md) and [current release notes](docs/RELEASE_NOTES.md).

The Pages workflow tests the real browser player at `/crisperplayer/` before deploying:

```sh
npm ci
npx playwright install chromium
npm test
node scripts/serve_site.js # http://127.0.0.1:8765/crisperplayer/
```

Browser tests import generated WAV files, exercise native browser playback, natural track
order, independent resume positions, bookmarks, export, deletion and a narrow viewport.
They also check that listening does not issue uploads.


To exercise native compressed-audio waveform extraction on this Mac, run
`python3 scripts/macos_waveform_smoke.py`. It generates an AAC tone with the
system encoder, writes it inside the test sandbox, checks measured/cached peaks
while the muted native player continues, and uses Brickwright signing. It leaves
your audiobook library untouched.


Development Android/iOS simulator snapshots are available by manually dispatching
**CI**. Ordinary pushes run source/tests/browser/CLI verification; immutable
version tags run the complete permanent release and internal TestFlight pipelines.
This avoids building duplicate development binaries alongside a tagged release.
