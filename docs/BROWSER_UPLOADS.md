# Upload audiobooks over Wi-Fi

In the installed app choose **Add books → Upload from browser**, or
**Settings → Upload from browser**. Connect the device and computer to the same
trusted private network, start sharing, and open the displayed HTTP address in
the computer's browser. Copy the access code from the device into the browser.
No account, cloud service, USB cable or browser extension is needed.

Select the audio files belonging to **one book** and optionally enter a title.
The page uploads the files sequentially with progress, then imports them through
the app's normal library importer. Tracks use natural filename order. Embedded
metadata, supported chapters and cover artwork use the normal import behavior.
Wait for the import confirmation before starting the next book. Files must have
unique names within a book. Supported formats match local audio import.

Limits: 4 GiB per file, 20 GiB per book and 500 files per book. Allow free space
for both the received files and the library's owned copy. File extensions are
checked; codec support still depends on the platform. ZIP archives are not
extracted. Retrying a filename replaces its unfinished-batch copy. After a
failed transfer retry the same selection, or stop/restart sharing to discard the
batch before selecting a different book.

Keep the transfer screen open and the device unlocked. Leaving the screen,
backgrounding the app or pressing Stop closes the server and deletes its inbox.
An import already committing to the library is allowed to finish. Sharing must
be restarted explicitly, with a fresh address/access code. An abrupt OS/process
termination may leave temporary files until the OS clears its temporary folder.

## Network and access

The server binds an OS-selected IPv4 port only after Start. Only loopback and
private/link-local IPv4 clients are accepted. It lists the device's private
addresses; if there are several interfaces, use the Wi-Fi address reachable by
the computer. No Bonjour advertisement, router port mapping or public hosting is
configured. Guest Wi-Fi/client isolation, VPNs and firewalls may block access.
On iOS allow Local Network access; test that permission on physical hardware.
On desktop permit incoming connections if the OS firewall asks.

A fresh 160-bit access code is required for every upload/import request. It is
not placed in the URL, browser storage or logs. The unauthenticated page contains
no library information. Host and Origin validation protect against browser
cross-origin requests and DNS rebinding. The server exposes no library download,
delete, arbitrary path access or playback-control endpoints. Upload bytes stream
to private, generated directories; client filenames never select directories.
One upload/import runs at a time, with file-count/size limits and an inactivity
timeout. Failed transfers are removed.

This is **HTTP**, so the access code and audio are not encrypted on the network.
Use only a trusted private network and stop sharing when finished. HTTPS with
self-signed certificates would require browser trust setup and is not enabled.

## Android, iOS and FTP/SFTP

Both Android and iOS support foreground sockets inside the app sandbox; this
feature deliberately uses the same foreground-only policy on desktop as well.
iOS does not provide an unrestricted background server mode. Audio playback
permission is not a guarantee that an upload server can remain reachable.
Android could support longer transfers with a dedicated foreground service and
persistent notification, but that service is not part of this implementation.

FTP and SFTP **servers are not included**. A sandboxed SFTP server is feasible
while the app is running, but needs an SSH server implementation, a persistent
host key, authentication and restricted file operations. Plain FTP transmits
credentials/audio without encryption and adds separate data-port handling.
An authenticated WebDAV upload server could provide file-manager compatibility
without an SSH stack in a future iteration. Existing WebDAV/SFTP/SMB client
sources remain available to download from a NAS.

Protocol and real-library import tests are in `test/browser_upload_test.dart`.
Physical iOS/Android transfers, permission prompts and lock/background behavior
still require device validation before treating this as production verified.

Platform references:
[Apple background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app),
[Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy),
[Android foreground-service time limits](https://developer.android.com/develop/background-work/services/fgs/timeout),
and [VLC Wi-Fi sharing](https://docs.videolan.me/vlc-user/desktop/3.0/en/gettingstarted/mobileoverview/ios/media_synchronization.html).

## Verification

```sh
flutter test test/browser_upload_test.dart
npx playwright test tests/web/uploads.spec.js
python3 scripts/macos_local.py test --test-file integration_test/browser_upload_test.dart
```

The native test uses an isolated library and a generated WAV, checks real native
duration probing, then backgrounds the screen and verifies the TCP listener has
closed while the imported library copy remains intact. The Mac helper selects
the Brickwright build keychain explicitly. After native integration tests,
`python3 scripts/macos_local.py build` restores the normal app entry point.
