# Browser player and progress backups

The [GitHub Pages player](https://crispstrobe.github.io/crisperplayer/) stores audio
and listening metadata locally in IndexedDB. Browser audio decoders determine codec
support. Import one book at a time; multiple files use natural filename order.
Use a regular browser window to save audio. WebKit private sessions cannot persist
audio blobs in IndexedDB ([upstream report](https://github.com/microsoft/playwright/issues/42795)).

## Back up and restore

1. Select a book and choose **Export progress**. Keep that JSON file and the original audio.
2. On another browser, or after clearing browser storage, add the original audio files again.
3. Select the imported book and choose **Restore progress**. Pick its JSON backup.
4. Review the matching tracks, position, speed, volume and number of bookmarks to add.
5. Choose **Restore this book**. Playback pauses at the restored position.

Cancel leaves playback and metadata untouched. Existing bookmarks are retained;
restored entries with the same track, position and label are deduplicated. The
browser's local book ID is retained, so a backup can be used after reimporting audio.
Audio files, other books and the local title are preserved. Individual bookmark labels
can be edited, and individual bookmarks can be deleted.

A restore validates track order, numeric ranges, bookmark positions and readable audio
metadata before showing the preview. New backups also check file sizes and audio
fingerprints. Wrong recordings and out-of-range positions are rejected before applying
changes. Storage errors roll back the pending metadata changes. Switching books while
a backup is being checked cancels that restore.

## Format and limits

Browser exports use `browserPlayer: true` and `schema: 2`, with track names, current
track/position in seconds, playback speed, volume/mute-restoration level, bookmarks,
and a `files` array containing sizes and fingerprints. No audio bytes are exported.

`fingerprintAlgorithm: sha256-first-last-128k-v1` hashes the first and last 128 KiB
of each track with SHA-256. Overlapping portions of short files are read once. Checks
run sequentially and read at most 256 KiB per track. Changes solely in the middle of
a larger track are outside this check. Keep the original audio as part of your backup.

Earlier `schema: 1` browser exports remain supported. Their preview explains that
only filenames and order can be checked; verify that the selected recording is the
original. Position and bookmark-duration validation still applies. A legacy backup
without volume fields preserves the current volume.

Backups are limited to 5 MiB, 10,000 tracks and 10,000 bookmarks. Labels are limited
to 200 characters. Imports accept finite positions, track indices in range, speeds
from 0.5 to 3.0, and volume from 0 to 1. Unknown backup versions are rejected.
Native app library exports use a separate format and are restored through the native app.

## Privacy and deployment

File checks, fingerprints, previews and restores run entirely in the browser. Neither
audio nor backups are uploaded. There are no third-party runtime JavaScript libraries
or listening analytics. GitHub Pages may keep normal hosting logs. The About dialog
contains provider/contact, privacy, source and license details.

The browser player is deployed independently of native binary releases. Changes to
`site/` run real-browser checks before the Pages deployment. Tests cover playback,
backup round trips, reimports, mute restoration, invalid input, wrong audio, failed
storage writes, interrupted restores, bookmark editing and small-screen layout.

For local browser checks, use the pinned dependencies from `package-lock.json`:

```sh
npm ci
npx playwright install chromium webkit
npm test
npm test -- --browser=webkit
```

WebKit tests use a new, temporary regular profile for each test so file storage
matches normal Safari browsing. The fixture deletes its own profile after the test
and never opens a user's Safari profile. Chromium tests use isolated contexts.
