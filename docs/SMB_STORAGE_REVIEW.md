# SMB storage review — 11 November 2026

CrisperPlayer pins CrispCloud's shared Dart transport at immutable commit
`13ca681f0c706cf24e65c7906f8a98e20421c590`. Its optional Rust backend uses the same
SMB core consumed directly by CrispSorter. There is no separate Dart SMB protocol
implementation. See [GUI/CLI choices and build instructions](SMB_RUST_ROLLOUT.md).

GUI settings and the authenticated desktop CLI update the same service and
persisted per-server backend choice: `libsmb2`, `rust`, or `auto`. Active transfers
prevent a backend change. Auto falls back only if the Rust native library cannot
load before login; authentication and security failures do not switch engines.

libsmb2 remains the default and fallback. The BSD dart_smb2 0.2.5+crisp.1 wrapper
ships LGPL-2.1-or-later libsmb2 r10. Apple builds use a pinned source recipe with
install-name padding; other platforms use verified release binaries. Package,
source and native build-input hashes are recorded in `licensing/` and checked in CI.
The fallback retains its native distribution obligations.

Offline transfers retain bounded reads, revision-validated resume and one active
audiobook import. Progress notifications coalesce into 100 ms windows while byte
accounting, pause checks and phase changes remain immediate. Tests cover settings
persistence, GUI controls, authenticated CLI commands, busy/invalid selection,
progress timers and remote-library behavior. CI also checks lockfile consistency
and the SMB source/license evidence.

Real SMB3 encryption interoperability, physical devices, signed release artifacts
and measured throughput/battery behavior remain qualification gates. Passing the
local SMB2 fixture does not justify changing the default engine.
