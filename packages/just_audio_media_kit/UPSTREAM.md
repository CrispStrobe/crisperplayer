# Maintained desktop audio adapter

This is the selected source closure of `just_audio_media_kit` **2.1.0**, with
local version **2.1.0+crisper.1**. The upstream package is published at
<https://pub.dev/packages/just_audio_media_kit/versions/2.1.0> and its repository
is <https://github.com/Pato05/just_audio_media_kit>.

The exact pub.dev archive URL, SHA-256, and hashes of all eight selected
unmodified upstream files are recorded in [UPSTREAM.json](UPSTREAM.json).
The retained [LICENSE](LICENSE) is **Unlicense**. The published archive includes
examples and screenshots which are not part of this local source closure. No
native binary is vendored here.

[UPSTREAM.patch](UPSTREAM.patch) records the changes and three new source/test
files against those originals. The patch adds an immutable processor selection
per native player, optional discovery from the loaded libmpv's filter inventory,
verification that an explicitly selected filter was installed, and cleanup/error
completion when initialization or loading fails. Runtime errors from the selected
processor, including mpv disabling its labeled filter, stop playback and retain
an error until that player is replaced. Loading fails promptly even if native
open is still pending; later buffering and completion events cannot erase the
failure. Null selection preserves the upstream `pitch` configuration behavior.

The optional portable modes require CrisperPlayer's source-built `crisperdsp`
mpv filter. Atempo requires mpv's tempo-aware `lavfi-tempo` wrapper and its linked
FFmpeg `atempo` implementation. Plain `lavfi=atempo` is deliberately excluded
because it does not implement mpv's speed-control/source-clock protocol. Filter
discovery is independent of platform names; unavailable choices never become
available merely because this Dart package is present.

When updating upstream, fetch and hash the complete release archive, review the
changed native transport behavior, regenerate the selected original-file hashes
and patch, update the dependency inventory, and rerun the adapter and native
desktop integration tests. `media_kit` and the chosen native libmpv/FFmpeg build
keep their own independent source and licensing records.
