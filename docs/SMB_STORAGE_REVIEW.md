# SMB storage review — 11 November 2026

## Current implementation
CrisperPlayer pins CrispCloud's `packages/crisp_storage` at
`ac90899f8110dcb266d122208b3b3a879a257eee`. The dependency closure includes
`dart_smb2 0.2.1`, which wraps LGPL-2.1 libsmb2; the wrapper's BSD license
does not replace the native license. Offline downloads use one scheduled
transfer, bounded SMB reads, revision-validated resume and local import.
SMB3 encryption is required by default; signing is enabled.

## Priorities
1. Coalesce byte-progress notifications so fast transfers do not rebuild the UI
   on every network chunk. Keep byte accounting and pause checks immediate,
   and publish phase changes without delay.
2. Improve shared transport disk writes in CrispCloud, then adopt a verified
   immutable commit with regenerated dependency/license evidence.
3. Retain one active audiobook import; increasing workers without measurement
   would add connections and memory pressure.

## Permissive replacement decision
Do not replace the engine with smb_connect merely to change its license:
its advertised SMB2.1 ceiling does not meet the existing SMB3 encryption
contract. Evaluate a pure Rust or Go SMB2/3 engine behind a shared adapter only
after signed/encrypted Windows/Samba/NAS tests, cancellation, resume validators,
path confinement, mobile packaging and the complete dependency-license closure
pass. SMBJ is Android-specific; the Swift SMBClient advertises SMB2.0.

This branch does not claim to remove LGPL. Existing notices and encryption
defaults remain required. No engine migration or dependency pin change is
implied by progress-notification optimization.
