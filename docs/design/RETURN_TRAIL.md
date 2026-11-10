# Return Trail: protected catch-up in the original narration

## Product decision

Get back into the story without losing your place. Return Trail builds a short,
inspectable listening session from passages actually played on this device. It
protects the normal resume point, plays original audio locally, and lets the
listener return to that point or explicitly continue from a reviewed passage.

This is a differentiation hypothesis, not a verified world-first claim. As of
2026-11-10, [Spotify offers tailored audiobook recaps](https://newsroom.spotify.com/2026-04-15/audiobook-charts-recaps-page-match-bookshop-update/),
[Bloox offers local catch-up summaries](https://blooxapp.com/),
[Prologue offers on-device transcription](https://prologue.audio/), and
[Voice offers playback history and one-tap return](https://voice.woitaschek.de/).
The opportunity is the combined experience: owned files, original narration,
verified played ranges, transparent source timing, protected progress, and
the same coordinator on Android, iOS, desktop and the desktop CLI.

## Scope of this feature branch

- Record bounded, physical-track playback ranges in SQLite. Start with new
  listening; legacy session endpoints cannot prove continuous audio coverage.
- Generate up to three recent excerpts for a chosen listening-time budget.
  Honor playback speed, known track durations, seek gaps and the current anchor.
- Show the source track/chapter, time range and selection reason before starting.
- Save a durable return bookmark before moving the decoder. Keep normal saved
  progress at the original anchor while reviewing, including background flushes.
- End the trail at the original anchor, paused. Allow an explicit early return
  or a deliberate “Continue from here”. Keep pause and sleep timers effective.
- Avoid queue advancement, automatic bookmarks and new trail coverage during
  review. Handle stale actions, decoder failure, book changes and unknown timing.
- Expose planning and the same actions through the authenticated desktop CLI.
- Migrate existing libraries in place, preserve metadata backup/restore, and
  clear recorded passages with listening history.

The browser player is a separate application and is not changed by this native
feature. There are no model downloads, transcription, external services or audio
uploads. Excerpt selection is based on recorded playback, not semantic story
understanding; it must not be presented as an AI summary or attention detection.

## Engineering invariants

1. Book ID, physical file and local offset identify the protected place. Unknown
   preceding track durations never require invented whole-book timing.
2. Capture boundaries reset on explicit seeks, pause, buffering, speed changes,
   source changes and review. Never fill a seek gap with inferred listening.
3. Progress is saved before entering review. Checkpoint, disposal and sync-facing
   database reads continue to see that saved progress until explicit adoption.
4. Review completion does not consume Up next or restart a finished book.
5. A deadline or interruption that pauses playback cannot be undone by a queued
   excerpt transition. Returning to the anchor leaves the decoder paused.
6. Persisted coverage is bounded per book and never claims the listener paid
   attention. The truthful label is “previously played passages”.

## Validation

Use production-coordinator tests with the existing SQLite/audio harness for
capture gaps, physical-track restoration, checkpoint protection, completion,
sleep/interruption behavior, failures and stale commands. Test the planner on
overlap, invalid ranges, missing files, unknown durations, budgets and speed.
Exercise migration, metadata round trips, CLI operations and narrow/large-text
Flutter layouts. Run the existing analyzer and relevant regression suites;
report actual validation separately from native-device acceptance still needed.

## Direction after this slice

Evaluate usefulness with listeners before adding complexity: does it reduce
manual scrubbing, does the listener recognize the passages, and can they always
recover their place? Potential follow-ups are opt-in sentence-boundary alignment,
user-selected memorable passages, portable trails tied to verified file identity,
and browser parity. Any semantic layer must cite the exact source passage and
respect both the saved anchor and actual played coverage.
