# Storage engines in CrisperPlayer

Recorded on 11 November 2026. SMB selection is implemented. The Filen/Internxt
Rust integration below is planned; documenting it does not add another engine
to their connection dialogs or CLI commands.

The complete cross-app contract, fallback table, licensing inventory boundaries
and migration/test sequence are recorded in
[CrispCloud's shared design](https://github.com/CrispStrobe/CrispCloud/blob/95f4574e58cd69881532603eb48689d43dfe8ead/docs/STORAGE_ENGINE_ARCHITECTURE.md).
That link pins the design revision, independently of the runtime dependency.

## Current Dart and Rust responsibilities

| Area | Current implementation |
| --- | --- |
| UI, settings and service lifetimes | Flutter/Dart and Riverpod |
| Remote library, download queue, staging and audiobook import | Dart application services; one active download/import workflow |
| Playback and local library | Existing Dart/native audio and database integrations; outside this provider migration |
| SMB | Shared Dart `SmbSession`: default dart_smb2 → C libsmb2, optional Dart → FFI → Rust |
| Filen | Dart `filen_client` through the app's remote adapter |
| Internxt | Dart `internxt_client` plus the app-specific session-renewal adapter |
| Desktop CLI | Dart control client calls the authenticated running application; it uses the GUI's service and stored connections |
| Browser | Separate Pages local-file player; Flutter Web displays an availability notice |

This is a responsibility map for storage, not an application-wide percentage.
In particular, the current SMB fallback is a C protocol library reached from
Dart; there is no pure Dart SMB engine.

[`pubspec.yaml`](../pubspec.yaml) pins `packages/crisp_storage` in CrispCloud at
`13ca681f0c706cf24e65c7906f8a98e20421c590`. Filen is a local vendored Dart package;
Internxt is pinned to Dart package 0.2.3. The relevant application boundaries are
[`remote_client.dart`](../lib/services/server/remote_client.dart),
[`remote_library_service.dart`](../lib/services/server/remote_library_service.dart)
and [`internxt_session_client.dart`](../lib/services/server/internxt_session_client.dart).

## Proposed shared Rust integration

Reuse the `crisp-filen` and `crisp-internxt` Rust clients already used by
CrispSorter, with a versioned shared source and a Dart bridge. Sorter calls those
libraries directly; the Flutter apps should call the same implementations.
Those clients are not currently dependencies of this app and have no generated
Filen/Internxt Dart bridge here yet.

Keep account settings, secure-store access, job persistence, playback, progress
presentation and audiobook import in Dart. Rust can own protocol sessions,
provider encryption, bounded transfer processing and validated resume/range
primitives. Authentication state is scoped to the original account; engine
selection must not connect a resumed job to another account.

Prefer native-to-staging-file transfers with handles and coalesced progress,
keeping large audio bodies out of repeated FFI/JSON copies. Use bounded streams
when the Dart consumer needs bytes. Preserve the current 100 ms progress
coalescing, immediate terminal/pause checks, managed-library transaction and
publication only after successful completion. The host queue owns job retries;
provider chunk retries must be bounded and must not multiply queue retries.

The existing Rust clients use blocking HTTP and need storage workers. Native
packaging, worker teardown, cancellation and platform sandbox/ABI support must
be tested. A bridge alone is not a mobile distribution integration or proof of
faster transfers; existing Dart crypto can already call platform implementations.

## Settings and fallback

Current SMB controls, build instructions and actual desktop CLI examples are in
[SMB_RUST_ROLLOUT.md](SMB_RUST_ROLLOUT.md): `libsmb2`, strict `rust`, and `auto`.
Auto handles Rust library/bridge unavailability before authentication; it never
switches engines after authentication, network, protocol or security failures.
The default remains libsmb2. Explicit Rust needs a build with its native library.

For Filen/Internxt, the proposed choices are `dart`, strict `rust`, and `auto` per
connection, with Dart retained as the initial default. These values are not
accepted by today's provider settings. When implemented, both GUI and desktop
CLI must update the same saved connection through `RemoteLibraryService`, omit
credentials from responses and reject invalid or busy changes.

Both Dart and Rust remain supported choices. Keep one default per provider and
an optional per-account override: **App default**, **Dart**, **Rust**, or **Auto**.
An absent override inherits the provider default, initially Dart. After platform
qualification, changing a provider default to Auto makes Rust preferred with
Dart fallback before authentication/work. Explicit account selections remain
unchanged. The default switch affects future sessions/jobs, not active transfers;
paused jobs must validate or restart incompatible checkpoints. Both GUI and CLI
must report the configured policy and effective engine. Removing an engine would
be a separate decision, not the assumed completion of the Rust migration.

Fallback may select an engine only before work starts, when Auto explicitly
permits the alternative and the same security/capability requirements hold.
Wrong credentials, revoked sessions, failed token renewal, corrupt data and
transfer errors must surface as errors. Never resubmit an upload, delete or move
through another engine after it may have reached the provider.

An active transfer keeps its engine. A paused transfer may resume after a user
changes engines only if the checkpoint format/version and provider/account/file
identity are compatible; otherwise restart safely or reject it. Do not assume
Dart and Rust credentials/session JSON or resume markers can be copied directly.
Version and validate any conversion, or ask the user to reconnect. Existing SMB
Rust/libsmb2 checkpoints are deliberately incompatible and restart safely.

Engine selection does not change how this app stores secrets or establish
cross-app account sharing. Keep credentials in the established secure store and
pass them only to the selected session. Logs may contain requested/effective
engine, outcome, duration and aggregate byte counts, not keys, passwords, bearer
tokens, serialized sessions, private remote paths or raw provider errors.

## Provider compatibility

Start with Filen browse/download/range operations for offline audiobook imports,
then cover writes used by encrypted folder progress sync. Test Dart upload → Rust
download and the reverse, including supported metadata/crypto versions. Preserve
2FA errors and the current macOS loader compatibility behavior during rollout;
see [the Dart Filen patch](../packages/filen_client/LOCAL_PATCH.md).

For Internxt, preserve the behavior characterized in
[`internxt_session_test.dart`](../test/internxt_session_test.dart). The current
adapter renews through an authenticated endpoint with a required client header,
validates account identity, persists the new session to secure storage and
coalesces concurrent renewal. Shared integration must cover these cases rather
than replacing that adapter with an untested refresh endpoint or session format.

Existing encrypted progress sync must use the same provider contract as remote
imports, including authenticated writes; see [CLOUD_SYNC.md](CLOUD_SYNC.md).

## Platform and license limits

The Pages local-file browser player does not gain cloud/NAS imports from this
native migration. Rust blocking HTTP is not browser WebAssembly support, and
the Dart Filen entry point imports `dart:io`; a browser provider needs its own
HTTP/crypto/CORS or configured-gateway work and tests. Keep native desktop/mobile
qualification separate from browser support.

Both existing Dart Filen/Internxt clients and the candidate Rust clients declare
MPL-2.0. It is file-level copyleft, not an MIT/Apache/BSD-style permissive grant;
see the [Mozilla FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/). The independent
SMB Rust core/bridge declares MIT OR Apache-2.0; its dependencies have their own
evidence. The BSD dart_smb2 wrapper still bundles LGPL libsmb2.

Moving code to Rust does not relicense it. Update exact source pins, package
manifests, license texts, transitive Cargo evidence, build inputs and final native
artifact hashes together when adopting an engine. Preserve the app's existing
license and ownership policy; third-party grants remain component-specific.

## Acceptance before changing defaults

- Run common contracts against both engines: listing, object identity, metadata,
  range/seek, byte equality, progress, cancellation and supported mutations.
- Test both cross-engine transfer directions, supported crypto versions, damaged
  data, changed sources, large files, bounded memory and disk/write failures.
- Cover 2FA, renewal/revocation, account changes, legacy settings, native-library
  absence, default flips preserving explicit overrides/active jobs, strict versus Auto behavior and incompatible sessions/checkpoints.
- Exercise GUI and the authenticated CLI against the same service, including
  persistence, secret-free output and active/queued-job setting guards.
- Verify Linux/macOS/Windows and supported Android/iOS ABIs/devices, native
  embedding/signing/sandboxing, and first audio/seek/CPU/memory measurements.

Existing checks include `remote_library_test.dart`, `remote_resume_test.dart`,
`progress_notifications_test.dart`, `internxt_session_test.dart`,
`smb_settings_test.dart` and the SMB connection widget test. The Filen/Internxt package conformance job below now provides the first
cross-engine crypto and HTTP tests. Passing SMB fixtures or the
current Player CI does not qualify that proposed provider bridge.


## Executable Dart / Rust package conformance

`.github/workflows/provider-conformance.yml` runs the shared, pinned
[provider conformance harness](https://github.com/CrispStrobe/crisp-cloud-rs/tree/f6add1b13c8a2f8ae3f0c74b4b4d83204197152f/conformance).
It tests this app’s vendored Filen SDK and published Internxt 0.2.3 against
the standalone Rust packages. It uses the app dependency pair, PointyCastle
4.0.0 / dart_pg 2.1.0, without changing runtime dependencies.

The same independent fixtures run through real package APIs and compiled Dart
CLI probes with software and native AES backends. Checks include password/key
derivation, metadata, empty and boundary-sized chunks, CTR streaming and ranges,
wrong keys, damaged data, Unicode, pagination, cache reuse, HTTP failures,
read retry and create/rename/move/trash payloads. Each engine decrypts the other
engines’ exports. Loopback mocks validate authentication and wire requests;
mutations denied with 403 must not be replayed. No live account is used.

Both GUI and CLI use these package formats. Package parity does not qualify an
app bridge, GUI settings, session migration, active-job engine selection, native
mobile packaging or every transfer/resume/cancellation path. Keep the existing
surface and provider tests, and the rollout gates above, before changing defaults.

CI publishes `report.md`, `report.json`, wire traces and resolved probe lockfiles.
Unexpected differences fail. Exact reviewed gaps remain visible and set
`promotion_ready` to false, even when both implementations share a permissive
parse bug. `--strict` fails on those gaps too. A green regression baseline is
not permission to switch defaults. Legacy text-secret encoding requires a
compatibility decision before any format change.

Reproduce from a checkout of the pinned harness, with Python 3.12+, stable Rust
and Dart 3.13.7. From this app repository’s root:

```sh
python -m pip install cryptography==50.0.0
python ../crisp-cloud-rs/conformance/run.py --pointycastle 4.0.0 --dart-pg 2.1.0 --dart-filen packages/filen_client --published-internxt 0.2.3
# Add --strict for the default-promotion gate.
```

Keep this harness commit pinned and advance it deliberately with the compatibility
report. Retain both language implementations and explicit engine choices.
