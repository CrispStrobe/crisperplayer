# Shared Rust SMB prototype

CrisperPlayer pins CrispCloud `13ca681f0c706cf24e65c7906f8a98e20421c590`.
This includes the independent Rust SMB engine and generated Dart adapter behind
`SmbSession`. Existing calls and credentials remain compatible. libsmb2 remains
the default; no Rust library is bundled by this change.

This guide covers the implemented SMB modes. The current Dart/Rust split and
proposed Filen/Internxt bridge, engine choices, session compatibility and
qualification sequence are in
[STORAGE_ENGINE_ARCHITECTURE.md](STORAGE_ENGINE_ARCHITECTURE.md).

For host qualification, run `dart run crisp_storage:build_smb` after package
resolution. It prints the local dynamic library path. Pass both
`--dart-define=CRISP_SMB_BACKEND=rust` and
`--dart-define=CRISP_SMB_LIBRARY=/absolute/path/to/library` to a developer build.
Do not distribute an app containing this developer-machine path.

`auto` may fall back only when the Rust library/bridge cannot load before any
connection is made. Rust authentication, network, protocol, signing or encryption
failures never trigger a second login through libsmb2. Strict `rust` fails if the
library is unavailable. The default `libsmb2` does not load Rust at all.

The shared Rust downloader keeps remote file bytes in native memory/disk with
bounded read-ahead, reducing Dart crossings. Existing progress coalescing remains
in place. Keep app staging/publication, cache identity and playback-state checks;
only publish a download after successful completion. Switching backends safely
restarts incompatible resume markers. Cancellation ends the Rust session; a new
session can resume the partial download.

Qualification before rollout: compare first playback, resume, seeking, throughput,
CPU and peak memory against libsmb2 on the same files/network; test Windows,
Samba and NAS signing/encryption policies; package and sign native artifacts for
each mobile/desktop ABI. Successful SMB3 encrypted transfers and physical-device
behavior are not established by the loopback SMB2 fixture.

The Dart dependency inventory includes the exact new MIT runtime packages and
updated shared-package pin. The native Rust component is explicitly pending
artifact/notice review. Keeping libsmb2 also keeps its existing LGPL obligations.
Full Flutter tests and dependency resolution run in `Shared SMB contract` CI;
local verification here used the independent Dart package and license-gate tests.

The pinned shared source contains `docs/SMB_RUST_ROLLOUT.md`, native qualification
CI, and exact license evidence for all 143 Cargo packages resolved by the bridge.

## Validation checkpoint — 11 November 2026

[The Player workflow at `fcbee1f`](https://github.com/CrispStrobe/crisperplayer/actions/runs/43013225459)
passed the shared SMB contract, authenticated CLI/settings and GUI selector
regressions, progress/remote-library tests, lockfile consistency, the 37
license-checker unit tests and SMB source/native-recipe evidence checks.

Shared native host/Apple and GUI/CLI validation is recorded in CrispCloud's
rollout guide. Existing SMB tests do not qualify the proposed Filen/Internxt
bridge. Real encrypted SMB3/NAS behavior, signed application artifacts and
physical-device checks remain qualification gates; no merge or release is
implied by these CI results.

## Selecting the path in the GUI and CLI

New SMB connections offer **libsmb2**, **Rust**, and **Auto** in the connection
sheet. Existing connections can be changed in **Settings → Sync / Servers**
using their SMB transport menu. The selection is saved with that connection in
the credential store. It takes effect when the next session starts. Pause active
or queued downloads before changing it; switching a paused job can restart its
incompatible checkpoint safely.

The desktop CLI controls the running app and therefore uses the same saved
profiles and service as the GUI (enable desktop CLI in the app first):

```sh
crisperplayer servers
crisperplayer server-settings CONNECTION_ID
crisperplayer server-settings CONNECTION_ID libsmb2
crisperplayer server-settings CONNECTION_ID rust
crisperplayer server-settings CONNECTION_ID auto
```

For new connections, `server-connect` JSON also accepts `"smbBackend":"rust"`.
Use its stdin JSON form for credentials. Settings responses omit credentials.
Invalid choices fail before saving; settings changes cannot alter an active
transfer. A saved explicit selection overrides `CRISP_SMB_BACKEND`; old profiles
without a selection use that build default (libsmb2 unless configured otherwise).
There is no SMB transport on Flutter Web. Rust requires a native-enabled build;
choosing it in an ordinary build fails explicitly. Auto only handles a missing
Rust library, never authentication or security failures.

`test/smb_settings_test.dart` exercises the real authenticated desktop control
server and shared service for all three choices, persistence, secret redaction,
invalid input and busy-transfer protection. `test/server_connection_ui_test.dart`
checks the actual connection selector. Both are part of the Shared SMB contract
workflow, alongside existing browse/download CLI and progress regression tests.

The settings screen labels legacy profiles as `build default`, because their
transport can be set by `CRISP_SMB_BACKEND`. An explicit saved choice always wins.
The earlier shared macOS install-name/header-padding failure is addressed by
the pinned source recipe below; subsequent macOS and iOS CI checks passed.
Final app bundling/signing and physical-device checks remain separate gates.

## Fallback packaging and verification

GUI and authenticated desktop CLI use the same shared transport and persisted
backend setting. The pinned shared source now includes dart_smb2 0.2.5+crisp.1:
Apple builds compile the r10 libsmb2 source with install-name padding; Linux,
Windows and Android use checksum-verified r10 binaries. Default and fallback
selection are unchanged. Apple compilation requires Xcode tools, Python 3, curl
and zip. See the pinned package's CRISP_PATCHES.md for source and license details.

The distribution inventory records the fork and build inputs. Locally compiled
Apple binaries need their own final hashes and LGPL distribution materials;
upstream binary hashes cannot be reused for rebuilt or re-signed artifacts.
