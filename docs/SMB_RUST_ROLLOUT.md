# Shared Rust SMB prototype

CrisperPlayer pins CrispCloud `4b44dc4d44ef05a18d2da2579d2e3b866b245643`.
This includes the independent Rust SMB engine and generated Dart adapter behind
`SmbSession`. Existing calls and credentials remain compatible. libsmb2 remains
the default; no Rust library is bundled by this change.

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

## Validation recorded for this checkpoint

- Shared package: 19 Dart tests passed, including both libsmb2 and Rust loopback
  transfers; Rust core unit tests and native bridge build passed.
- Player's two adapter-contract assertions passed with the standalone Dart test
  runner. This is not a full Flutter test run.
- All 37 distribution-license checker unit tests passed.
- Full app package resolution, Flutter tests and final native artifacts remain
  CI/device qualification gates; no release or merge is implied.

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
The shared macOS Dart test job currently exposes an upstream prebuilt libsmb2
install-name/header-padding failure. Keep macOS native-asset packaging as a
blocking rollout check; passing Linux fixture tests does not clear that gate.
