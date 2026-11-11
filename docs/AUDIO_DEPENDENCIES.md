# Audio dependency boundaries and permissive decoder choices

Checked 11 November 2026 on `feature/portable-speed-engines`. This separates
the licenses of Dart packages, compiled native payloads and host libraries.
It is a source/build inventory, not a claim that every release artifact has
completed its license review.

Codec patents are tracked separately in [the patent and OS-decoder
record](AUDIO_PATENTS.md). In particular, the currently bundled Glint AAC-LC
decoder has **not** received patent clearance; resolving the Apache table
provenance did not establish patent coverage.

## media_kit is MIT

The former `media_kit` 1.2.6 package is **MIT**. The former
`just_audio_media_kit` 2.1.0 adapter is **Unlicense**. Their native libmpv/FFmpeg
dependencies have separate licenses; neither wrapper relicenses that payload.

- [media_kit's MIT license](https://github.com/media-kit/media-kit/blob/main/media_kit/LICENSE)
  and [native implementation](https://github.com/media-kit/media-kit#implementation).
- [just_audio_media_kit's Unlicense](https://github.com/Pato05/just_audio_media_kit/blob/main/LICENSE).
- [mpv's own licensing record](https://github.com/mpv-player/mpv/blob/master/Copyright):
  default GPL; an LGPL build excludes GPL-only files and must also select
  compatible dependencies.
- [FFmpeg's own licensing record](https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md):
  LGPL by default; optional GPL components and version-3 choices affect the
  resulting build.

The old Windows DLL evidence identified an LGPL-3.0-or-later candidate, while
the old Linux system libmpv depended on the distribution's build. Those
identities are historical records in `licensing/native_artifacts.json`.
The direct Dart/native migration removed the current libmpv/FFmpeg playback
dependency; media_kit's own license was not the reason its wrapper was removed.

## What LGPL remains

### Bundled SMB client

The confirmed active bundled LGPL component is **libsmb2**, used for SMB/NAS:

`crisperplayer → crisp_storage → dart_smb2 0.2.1 → libsmb2-r9`

`dart_smb2` is a BSD-3-Clause wrapper. Its build hook selects bundled native
assets for Android, iOS, macOS, Linux and Windows; the libsmb2 client library
is **LGPL-2.1-or-later**. This is separate from playback and is not made
permissive by the wrapper or the owner's rights in crisp_storage.

The successful Linux bundle audit at feature commit `494a32d` explicitly lists
`lib/libdart_smb2.so`. It contains no mpv/FFmpeg payload. The source/build-hook
configuration establishes the other platform targets; this particular bundle
is Linux evidence only.

The [native CI evidence](../licensing/evidence/native_audio_ci_2026-11-11.json)
retains the exact reports, PR merge revision and later JACK-removal validation.

Sources: [pinned storage dependency](https://github.com/CrispStrobe/CrispCloud/blob/ac90899f8110dcb266d122208b3b3a879a257eee/packages/crisp_storage/pubspec.yaml),
[libsmb2 licensing](https://github.com/sahlberg/libsmb2/blob/e94eee9465d55ed094ace2c038a8705b4822dada/COPYING),
and [current native inventory](../licensing/native_artifacts.json).

### Linux host/runtime libraries

The Linux desktop still uses system LGPL libraries. They are distinct from
the selected decoder/DSP source closure and were not copied into the audited
Flutter bundle:

| Host component | Why it is used | License boundary |
| --- | --- | --- |
| GTK3/GDK and GLib/GObject/GIO | Flutter's Linux window and event-loop integration | LGPL-2.1-or-later; their transitive system dependencies also require an exact release-host inventory |
| libsecret | Linux secure storage through `flutter_secure_storage_linux` | LGPL-2.1-or-later; includes further host dependencies |
| libpulse and/or libasound | miniaudio's native Linux output backends, loaded dynamically | LGPL client libraries; which backend is used depends on the host |
| GNU libc and libm on glibc-based distributions | The Linux native runtime and math functions | Principally LGPL-2.1-or-later, with additional permissive file grants |

GTK's wider host graph can include Pango, GdkPixbuf, ATK/AT-SPI, FriBidi and
other LGPL components. This is not an exhaustive transitive ELF inventory:
the CI artifact contains the bundle audit report, not all host shared objects.
Do not turn a source declaration or a local reference host into an exact claim
about every distribution. libstdc++/libgcc have GCC runtime-exception licensing;
they must not be mislabeled as LGPL.

Primary sources: [GTK3](https://docs.gtk.org/gtk3/),
[GLib](https://docs.gtk.org/glib/),
[libsecret](https://gnome.pages.gitlab.gnome.org/libsecret/),
[PulseAudio client/server distinction](https://github.com/pulseaudio/pulseaudio/blob/master/LICENSE),
[ALSA library license](https://github.com/alsa-project/alsa-lib/blob/master/COPYING),
[GNU libc source notices](https://sourceware.org/git/?p=glibc.git;a=blob;f=COPYING.LIB;hb=HEAD).

### Optional JACK fallback removed

miniaudio's default configuration also compiled an optional JACK client
backend. The owned output configuration now defines `MA_NO_JACK`; the
vendored miniaudio header is unchanged. This removes the optional JACK client
load from actual Windows/Linux playback. A macOS host test build previously
compiled it too, but the macOS app uses its Apple adapter.

Windows keeps native Windows output; Linux keeps PulseAudio/ALSA. The rebuilt
Linux library has no JACK loader/API markers, retains the Linux native audio
backends, and passes the native/Dart playback checks. JACK's client library
is LGPL, while its server has a separate GPL license; neither is bundled by
this application. [JACK's own API/license explanation](https://jackaudio.org/api/).

JACK connects audio applications in a low-latency routing graph. It is useful
for deliberate DAW/effects routing or a JACK-only studio setup, rather than
adding file formats or speed engines. The old miniaudio selection tried native
Windows output, or Linux PulseAudio/ALSA, before JACK; it did not expose an app
backend selector. Normal PipeWire desktops can already serve PulseAudio
clients through [pipewire-pulse](https://pipewire.pages.freedesktop.org/pipewire/page_man_pipewire-pulse_1.html).
Keep JACK disabled by default. A future opt-in needs a deliberate selector and
tests for server loss, buffer-size changes and source-time accounting.

### Other licenses and unfinished inventories

Bungee Basic, selected Eigen Core, Filen and Internxt include MPL-2.0 code.
MPL is not LGPL, but it is also not MIT/BSD-style permissive licensing. Those
existing choices are separate from the stricter rule for new decoder additions.

The Flutter engine/aggregate notices and some platform-native dependency
graphs still have incomplete artifact reviews. An unresolved inventory is not
proof of an LGPL component, and it does not justify a blanket LGPL-free claim.

## Rule for additional decoders

Glint is one implementation behind `PcmDecoder`, not an exclusive dependency.
New external decoder integrations must have an explicitly selected permissive
source closure: MIT, Apache-2.0, BSD-2-Clause/BSD-3-Clause, ISC, zlib, MIT-0,
Unlicense, CC0 or a separately reviewed equivalent. This includes transitive
libraries, extracted tables and copied native code, not only a package wrapper.
Keep immutable source hashes and complete original notices.

GPL, LGPL and MPL are not eligible for **new decoder additions** under this
rule. A custom codec license is not automatically accepted as similar. The
existing approved MPL DSP choices and platform system libraries keep their
separate policy scope.

## Prioritized alternatives and additions

These are researched candidates, **not implemented codecs** in this branch.

| Priority | Decoder source closure | License | Benefit and implementation boundary |
| --- | --- | --- | --- |
| 1 | libopusfile + libopus + libogg | BSD-3-Clause | Ogg Opus, sample seeking, pre-skip/end trimming and chained streams. Disable HTTP/opusurl so the app owns I/O and no optional OpenSSL dependency is added. |
| 2 | libvorbisfile + libvorbis + libogg | BSD-3-Clause | Ogg Vorbis; shares libogg. Incremental float decode and 64-bit PCM positions suit long books. Handle or explicitly reject chained format changes. |
| 3 | Apple ALAC reference decoder | Apache-2.0 | ALAC in M4A/M4B after extending the MP4 sample entry/magic-cookie path. The codec alone is not an MP4 demuxer. |
| 4 | dr_flac, or the libFLAC library source closure | MIT-0/Unlicense for dr_flac; BSD for libFLAC | Broader FLAC/Ogg-FLAC coverage. Preserve bounded reads/seeks and explicitly resolve unknown stream length. Select library code rather than differently licensed CLI tools. |
| Lower | dr_mp3 or minimp3 | MIT-0/Unlicense for dr_mp3; CC0 for minimp3 | Independent MP3 compatibility/reference paths if tests justify them; they do not fill a currently missing format. |
| Deferred pending patent/distribution decision | Ittiam/AOSP libxaac decoder/common sources | Apache-2.0 | Broader AAC-LC/HE-AAC/USAC decoding, but the source license does not establish complete codec patent coverage. Prefer OS decoding on Android/Apple/Windows; do not add a default bundled AAC fallback merely to increase format count. |

Primary sources: [Opus licenses](https://opus-codec.org/license/),
[opusfile dependency split](https://github.com/xiph/opusfile),
[Vorbis libraries](https://github.com/xiph/vorbis),
[libxaac](https://github.com/ittiam-systems/libxaac/tree/2fbadd57bca46693b7a077bcf1513131106d960c),
[Apple ALAC](https://github.com/macosforge/alac/tree/c38887c5c5e64a4b31108733bd79ca9b2496d987),
[dr_libs](https://github.com/mackron/dr_libs/tree/f12e197fd462e4c22873fbd70d11b1d2f2c1dc3c),
[FLAC license split](https://xiph.org/flac/license.html),
[minimp3](https://github.com/lieff/minimp3/tree/ea99364f61c14656440e8d77e9c233ccf3124633).

For Vorbis, the full Xiph file decoder is preferable here to the smaller
stb_vorbis candidate: stb_vorbis documents absent chained-stream support,
ignored initial lossless truncation and 32-bit sample positions. For AAC,
FDK-AAC's custom license is not simply Apache/MIT/BSD and is not a default
substitute under this rule. Source license identification is separate from
any codec patent analysis.

Every added decoder must preserve bounded memory, cancellable I/O, original
source-time seeking, finite EOF handling and the existing mono/stereo DSP
contract. Codec selection remains independent of Sonic/WSOLA/Signalsmith/Bungee
selection; decoder additions need not change the transport or output layer.
