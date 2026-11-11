# Shared Rust SMB prototype

CrisperPlayer pins CrispCloud `ffeae11d53054190cf6f3a6fbcec2eb44b32dfb2`.
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
