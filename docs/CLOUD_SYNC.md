# Listening progress sync

Sync is optional. Listening and local progress saves work without a network.
The native app supports Plex progress and encrypted progress files in your own
Nextcloud/WebDAV, Filen or Internxt folder. The browser player currently uses
its separate manual progress backup/restore format.

## Plex

Download a book from Plex first. In **Cloud, servers & NAS → Plex progress sync**,
enable its connection and press **Sync now**. The Plex music library must have
**Store track progress** enabled. The app verifies that Plex retained a pushed
position; it does not acknowledge a server that silently discards progress.

Progress follows the original Plex album/track identity, disc and track order.
A changed track count, identity or known duration stops syncing that book.
One media part per Plex track is supported. Re-import changed server content.
A durable local baseline compares both sides: changes on one side transfer;
changes on both sides require **Use this device** or **Use Plex**. A rewind is a
valid change, so the larger position does not automatically win. Plex has no
atomic compare-and-swap for this API; simultaneous server writes during a push
remain a limitation. Avoid actively playing the same Plex book on two devices.

Incoming progress never seeks an open book. Close it or use the explicit
**Apply Plex position** action, which reloads it paused. Enabled connections
retry every 30 seconds while the native process is running. These are server
progress writes, not end-to-end encryption against the Plex server owner.

## Encrypted folder sync

1. Add a Nextcloud, WebDAV, Filen or Internxt connection. Nextcloud accepts the
   account base URL and username/app password; its DAV endpoint is added for you.
2. Create a dedicated, existing folder through that provider, then choose
   **Encrypted cloud progress sync → Set up**. Enter that folder's path and a
   shared passphrase of at least 12 characters.
3. Add the corresponding connection/folder on each other native device and use
   the exact same passphrase. Import or download the same audio on each device.
4. Press **Sync now**. Automatic retries run once a minute while the app runs.

The first sync streams SHA-256 over each audio file. Results are cached by path,
size and modification time. A book matches by the ordered content hashes of its
tracks, regardless of local filenames, title or device paths. Re-encoded or
retagged audio has a different identity; it must be copied unchanged to match.
Unknown track durations must be measured through playback before that book syncs.
Only track-relative position, measured durations and vector clocks are synced.
Bookmarks, history, playback preferences, finished overrides, artwork and audio
are not part of this first progress format. Native metadata backups cover those
separately. Do not enable both Plex and folder sync for the same library until
you have chosen which source should own its positions.

Snapshots use AES-256-GCM with fresh nonces, a random 128-bit salt per device and
PBKDF2-HMAC-SHA256 (210,000 iterations). Derivation runs off the UI isolate; derived keys are cached only in memory.
The passphrase stays in platform secure
storage; this Mac's local build uses the explicit Brickwright keychain.
The provider sees encrypted snapshot files. Filen/Internxt also use their own
provider encryption through the same SDK projects as CrispCloud. The shared
passphrase cannot be recovered; keep it safely. Changing it does not decrypt
old snapshots. Use a new dedicated folder for a new passphrase.

Each device has its own random ID and monotonically numbered snapshots.
Progress uses vector clocks, not device wall clocks. Concurrent positions require
an explicit choice. No source wins solely because it is further into the book.
The new encrypted file is read back and authenticated before publication is
acknowledged. A device retains its latest two snapshots and deletes only its own
older snapshots. No audiobook or other user file is deleted by sync.
The folder should be shared only among your own devices; anyone with its
passphrase can read and write progress. Corrupt or unauthenticated snapshots
stop that sync attempt and preserve local progress.

Sync applies matching books that are closed. Open books show an explicit
**Apply incoming** action. Offline changes and clocks are journaled before
network requests and survive process restarts. Background scheduling is best
effort: these timers do not keep a terminated/suspended app alive.

## Desktop CLI

Use `call … -` to read JSON from stdin, particularly for credentials/passphrases.
The running app owns the same services used by the GUI.

```sh
crisperplayer call sync-status '{}'
crisperplayer call sync-enable '{"connectionId":"ID","enabled":true}'
crisperplayer call sync-now '{}'
crisperplayer call sync-resolve '{"bookId":"ID","choice":"local"}'

crisperplayer call folder-sync-status '{}'
crisperplayer call folder-sync-configure -
# stdin: {"connectionId":"ID","folder":"/CrisperPlayerSync","passphrase":"YOUR SHARED PASSPHRASE"}
crisperplayer call folder-sync-now '{}'
crisperplayer call folder-sync-resolve '{"bookId":"ID","choice":"local"}'
# To choose an incoming candidate, use its opaque `choice` from folder-sync-status.
crisperplayer call folder-sync-configure '{}'
# Empty configuration disables folder sync; local progress remains.
```

The older hosted-account/backend proposal is archived as
[an unimplemented design](design/HOSTED_SYNC_PROPOSAL.md). It describes no active
service and should not be used as a statement of current encryption or features.
