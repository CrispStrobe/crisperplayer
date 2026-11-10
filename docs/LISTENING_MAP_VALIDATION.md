# Listening map validation

Validated on 10 November 2026 with Flutter 3.44.4 and Dart 3.12.2.
The implementation is on `feature/return-trail` and has not been released.

## Completed checks

| Check | Result |
| --- | --- |
| Combined coverage, migration, playback, navigation and layout suites below | 95 tests passed |
| Data-layer regression run including existing Return Trail service tests | 40 tests passed |
| `flutter analyze --no-pub` | No issues found |
| `dart build cli -o build/cli` | Bundle compiled; executable help lists coverage commands |
| `git diff --check` | Clean |
| Native Flutter visual inspection | Player, map and selected gap rendered at 390 × 844 with Roboto/MaterialIcons |
| Accessibility checks | Keyboard and screen-reader selection, 200% text, expanded gap rows and fixed player transport passed |

The data-layer run overlaps the combined run; these counts are not additive.
The combined command was:

```sh
flutter test --no-pub \
  test/listening_coverage_service_test.dart \
  test/listening_coverage_playback_test.dart \
  test/listening_coverage_cli_test.dart \
  test/listening_coverage_ui_test.dart \
  test/database_migration_test.dart \
  test/return_trail_import_test.dart \
  test/return_trail_playback_test.dart \
  test/playback_logic_test.dart \
  test/sleep_timer_test.dart \
  test/player_layout_test.dart \
  test/accessibility_test.dart
```

The checks cover exact unions and complements; overlap counted once; source
seeks, paused intervals and buffering left unfilled; retained coverage after
206 distinct passages roll the recent buffer past its 200-passage cap; schema
1–5 upgrades; validated backup merge and file-path remapping; history clearing;
unknown durations; Return Trail isolation; native completion and adjacent-track
boundaries; manual track changes; stale map actions; paused jumps; live UI
updates; next-gap wrapping; exact integer percentages; and subsecond gap labels.

## CI and acceptance limits

GitHub CI passed for the preceding Return Trail implementation at `07a4458`
([run 56](https://github.com/CrispStrobe/crisperplayer/actions/runs/42843179307))
and the cumulative-coverage data checkpoint at `72eebe0`
([run 57](https://github.com/CrispStrobe/crisperplayer/actions/runs/42848193980)).
Check the latest run on [pull request 1](https://github.com/CrispStrobe/crisperplayer/pull/1)
for the final UI and coordinator commit; a previous green checkpoint does not
establish the result of a later commit.

The local full-suite and Chromium limitations from the preceding run remain
documented in [Return Trail validation](RETURN_TRAIL_VALIDATION.md). The
combined targeted run above completes in this environment. No native-device
release build or real-decoder acceptance was performed for Listening map.
Before release, verify continuous playback across file ends, seeking,
background checkpoints, interruptions, native silence skipping and history
clearing on supported backends. Coverage is conservative recorded playback
evidence, not an attention measurement or a sample-accurate audit.

Screenshots in [Listening map](LISTENING_MAP.md) are actual Flutter renders with
fictional fixture metadata. The temporary capture script was removed.
