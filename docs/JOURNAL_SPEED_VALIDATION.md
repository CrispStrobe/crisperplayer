# Listening journal and speed controls: validation

Validated on 10 November 2026 using Flutter 3.44.4 and Dart 3.12.2.
The feature branch is `feature/return-trail`; these features are not a native
device release.

## Completed checks

| Check | Result |
| --- | --- |
| Combined feature and regression command below | **174 passed, 1 optional screenshot test skipped** |
| Separate journal UI run with capture enabled | **10 passed**, including actual widget screenshots |
| `flutter analyze --no-pub` | No issues found |
| `dart build cli -o build/cli` | Compiled; executable help lists journal, map and trail commands |
| `flutter build web --no-wasm-dry-run --no-pub` | Built the native app's platform-availability web target |
| Actual Flutter visual inspection | Journal filters/entries and speed/processing screens at 390 × 844 with Roboto/MaterialIcons |
| Accessibility | Journal at 320 × 568 with 200% text; existing player/speed landscape and screen-reader checks passed |
| `git diff --check` | Clean |

The combined command was:

```sh
flutter test --no-pub \
  test/listening_journal_service_test.dart \
  test/listening_journal_playback_test.dart \
  test/listening_journal_cli_test.dart \
  test/listening_journal_ui_test.dart \
  test/speed_controls_test.dart \
  test/database_export_snapshot_test.dart \
  test/database_migration_test.dart \
  test/listening_coverage_service_test.dart \
  test/listening_coverage_playback_test.dart \
  test/listening_coverage_cli_test.dart \
  test/listening_coverage_ui_test.dart \
  test/return_trail_service_test.dart \
  test/return_trail_playback_test.dart \
  test/return_trail_cli_test.dart \
  test/return_trail_ui_test.dart \
  test/return_trail_import_test.dart \
  test/played_range_recorder_test.dart \
  test/playback_logic_test.dart \
  test/sleep_timer_test.dart \
  test/player_layout_test.dart \
  test/accessibility_test.dart
```

## What these checks establish

Journal checks cover default-off recording; live opt-in/out without backfill;
stable checkpoint UUIDs; repeated playback retained separately; recorded
source/destination jumps; pauses and buffering left out of played ranges;
speed boundaries; labeled Return Trail replay and return navigation; more than
200 retained passages; a year-old stop reopened across books with a recovery
bookmark; stale/invalid positions; unknown-duration evidence; cleared records
not revived by pending writes; date overlap; stable pagination; title snapshots;
schema 1–6 upgrades; and validated backup merges and path remapping.

The export regression interleaves a concurrent book/journal import between
table reads and confirms the backup restores as one consistent snapshot.

Speed checks verify supported desktop startup configuration, exact/hundredth
entry, decimal commas, 0.05× increments, per-book persistence, external control
updates, failed backend requests, stale-book controls and the pending-restart
selection. Pinned native package sources were inspected to identify Android,
Apple and desktop routes; see [speed processing](SPEED_PROCESSING.md).

## CI and practical limits

GitHub CI passed for the Listening map implementation at `4160ce1`
([run 58](https://github.com/CrispStrobe/crisperplayer/actions/runs/42849784884))
and the durable journal data checkpoint at `7413f75`
([run 59](https://github.com/CrispStrobe/crisperplayer/actions/runs/42857592295)).
Consult the current checks on [PR 1](https://github.com/CrispStrobe/crisperplayer/pull/1)
for later implementation and documentation commits.

The earlier full local suite and Chromium sandbox limits remain described in
[Return Trail validation](RETURN_TRAIL_VALIDATION.md). The final combined suite
above completes successfully in this environment. Counts from earlier targeted
runs overlap and must not be added to the 174 result.

No native-device release build, real-decoder listening acceptance, controlled
audio comparison or CPU/battery benchmark was performed here. Before release,
verify the desktop processor choice after restart, pitch preservation across
supported rates, native file transitions, background/lock-screen controls,
interruptions and sleep timers. Automated tests and source inspection do not
establish that one algorithm sounds better for every recording or listener.

All screenshots use fictional book metadata. The journal screenshot test is
optional and runs when `CRISPER_JOURNAL_SCREENSHOT_DIR` is supplied; it was
enabled and inspected separately. No personal library content is included.
