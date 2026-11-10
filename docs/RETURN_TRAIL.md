# Return Trail

**Get back into the story without losing your place.**

Open a book in the installed app and choose **Return Trail** on the player.
Select 30 seconds, one minute or two minutes of catch-up time. The preview shows
up to three passages, their source chapter or track, exact track-local times,
and why each was selected. The budget accounts for your playback speed; if less
eligible audio is available, the preview shows the shorter actual estimate.

Choose **Start Return Trail** to listen in the original narrator's voice.
Your usual resume point stays saved while you review. You can close the sheet
and reopen it from the player card; pausing and resuming still work.

- **Next passage** advances through the trail.
- **Return to my place** restores the saved file and position, paused.
- **Continue from here** adopts the reviewed position and continues playback.
- Reaching the end of the trail returns to your saved place, paused.

During a trail, ordinary seeking stays within the current excerpt and next/
previous transport controls navigate the excerpts. Finish the trail to resume
normal chapter navigation. Sleep timers and interruptions can still pause the
audio. Review never consumes Up next, records automatic bookmarks or replaces
your normal progress with a temporary review position.

## What the passages mean

Return Trail uses new playback ranges recorded on this device. It does not
infer that everything between old history endpoints played: a forward seek may
have skipped that audio. A new installation or an existing book with no new
listening therefore starts with an honest empty trail. Listen normally to build
one; imported legacy history alone does not populate it.

The planner chooses recent played passages, removes overlapping ranges, and
caps them at your current physical file and offset. It skips files no longer
listed in the book. Unknown preceding track durations do not prevent a return:
the physical file and local position identify your place.

This is source-based context replay, not a generated summary. It does not know
the plot, detect attention, or promise sentence-aligned cuts. Excerpt transitions
use decoder position events and a speed-adjusted timer; native scheduling may
introduce a small boundary delay. The plan itself never extends beyond the saved
anchor. Native-device playback acceptance remains necessary for each backend.

## Storage and recovery

Recorded passages stay in the local SQLite database, bounded to the 200 most
recent ranges per book. They are included in explicit library metadata backups
and removed when you clear listening history or delete the book. They are not
uploaded by progress sync. No transcription, account, model or network request
is needed to create or play a trail.

Before reviewing, the app saves normal progress and adds a **Return Trail ·
saved place** bookmark. Up to five such bookmarks are retained per book. If the
app closes during review, the regular resume point still opens at that saved
place. The bookmark also gives you a visible recovery point after a decoder
error. Audio files remain necessary for playback and metadata restores.

This feature is available in the native Flutter app and its desktop CLI. The
separate Pages browser player does not yet have Return Trail.

## Desktop CLI

With the desktop app running and CLI enabled:

```sh
crisperplayer trail-plan 60  # inspect source passages; does not move playback
crisperplayer trail-start 60
crisperplayer pause
crisperplayer play          # resume the active trail
crisperplayer trail-next
crisperplayer trail-return  # restore the protected place, paused

crisperplayer trail-start 30
crisperplayer trail-continue # explicitly keep the reviewed position and play
```

Budgets can be any 15–300 listening seconds. `status.returnTrail` reports active
state, zero-based clip index and the full plan. `trail-plan` returns source paths,
track indices, millisecond ranges, selection reasons, speed and estimated time.
For delayed automation, pass `bookId` with structured calls so an action rejects
a stale selected book:

```sh
crisperplayer call trail-start '{"bookId":"BOOK_ID","seconds":60}'
```

See [the product and engineering rationale](design/RETURN_TRAIL.md).
