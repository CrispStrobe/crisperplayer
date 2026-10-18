# Releases and installation

Get downloads from [GitHub Releases](https://github.com/CrispStrobe/crisperplayer/releases/latest).
Every public binary release contains a signed Android APK, complete Windows x64,
Linux x64, Mac arm64 and Mac x64 app archives, separate CLI archives, native notices,
public Android certificate details and `SHA256SUMS.txt`.
Archives include app libraries/assets and the CLI's native assets; do not distribute
only an executable. `BUILD.json` records the version, build and exact Git revision.

## Install

- **Android:** install `CrisperPlayer-android.apk`, allowing installation from your download
  source if Android asks. Public APK updates retain the release signing key. Earlier
  debug-signed CI artifacts require migration; see [Android signing](ANDROID_BUILD.md).
- **Windows x64:** extract the entire ZIP and run `CrisperPlayer/crisperplayer.exe`.
  Keep the DLLs and `data` directory together. Windows downloads are unsigned.
  Install the [Microsoft Visual C++ Redistributable (x64)](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist)
  if it is not already installed (including when Windows reports missing `VCRUNTIME140`
  or `MSVCP140`). These system runtime prerequisites apply to the ZIP distribution;
  the archive is not an installer. See [Flutter's Windows distribution guidance](https://docs.flutter.dev/platform-integration/windows/building#building-your-own-zip-file-for-windows).
- **Mac:** choose arm64 for Apple silicon or x64 for Intel. Extract the ZIP and move
  `CrisperPlayer/crisperplayer.app` to Applications. Public downloads are ad-hoc signed
  but not notarized; macOS may block them. Review the source/checksum before allowing
  the app through System Settings → Privacy & Security. A Developer ID signing and
  notarization setup is still required for routine Gatekeeper-trusted distribution.
- **Linux x64:** extract the tar archive, install runtime dependencies (for Ubuntu/Debian:
  `sudo apt install libmpv2 libgtk-3-0 libsecret-1-0`), then run
  `CrisperPlayer/crisperplayer`. Other distributions may use different package names.
  These binaries are built on Ubuntu 24.04 and require compatible system libraries.
- **CLI:** desktop archives include `cli/bin/crisperplayer` (`.exe` on Windows).
  Keep the complete CLI bundle together. Start the GUI first: the CLI controls its
  authenticated loopback service, library and audio backend. It is not a separate
  headless decoder. Dedicated CLI archives are also attached.
- **iOS:** distributed through internal TestFlight for authorized App Store Connect
  team testers. An App Store-signed IPA is not a general sideload installer; it is
  retained as an Actions artifact in the iOS workflow, not advertised as a public download.
- **Web:** [GitHub Pages](https://crispstrobe.github.io/crisperplayer/) is a standalone
  local-file browser player. It has no NAS/embedded-chapter/native-library parity.

Verify downloads with `shasum -a 256 -c SHA256SUMS.txt` (Mac) or
`sha256sum -c SHA256SUMS.txt` (Linux), after downloading the listed assets. Windows
can use `Get-FileHash PATH -Algorithm SHA256` and compare with the manifest.

## Publish a version

1. Update `pubspec.yaml` to a unique version/build, for example `0.1.0+13`.
   Never reuse an uploaded iOS build number. Update `docs/RELEASE_NOTES.md` and relevant docs.
2. Run `flutter analyze`, `flutter test`, Python checks in `scripts/tests`, and `npm test`.
   Use the isolated SFTP/SMB test interpreters described in the README.
3. Commit and push master; confirm CI. Tag that exact commit to match the full pubspec
   version: `git tag v0.1.0+13` then `git push origin v0.1.0+13`.
4. `release.yml` validates the tag, prepares a draft, repeats checks, builds every required
   platform, hashes assets, then publishes the complete release as latest. A failed
   platform leaves the draft unpublished. Fix the issue and use a fresh build/tag if
   source changes are necessary; do not move a published tag.
5. The same tag triggers `ios-release.yml`: existing App Store identity, profiles,
   entitlement validation, upload, processing, and internal TestFlight group assignment.
   Do not dispatch another upload of the same build. Retry only distribution when the
   binary is already uploaded. See [iOS build](IOS_BUILD.md).

`Release binaries` also supports manual dispatch with an **existing matching tag** to retry
builds without changing the release source. The iOS workflow is independent: public
native releases can finish while Apple processing or internal distribution is pending.
Regular CI artifacts are development snapshots, not permanent release download links.

## Pages and repository metadata

The repository's Pages build source is **GitHub Actions**. `pages.yml` tests the site
on pushes that change `site/` or its browser checks, then uploads/deploys static files.
It uses project-relative assets and is tested at `/crisperplayer/`. No runtime server,
API key, app credentials or backend is published. The site links to stable latest-release
asset names. Keep those names in sync with `scripts/release.py`.

Use `npm ci`, `npx playwright install chromium`, and `npm test` locally.
`node scripts/serve_site.js` serves the site at `http://127.0.0.1:8765/crisperplayer/`.
Browser audio/progress lives in IndexedDB on that origin. Clearing site data or browser
storage eviction can remove it; exports contain metadata only. Hosting logs are managed
by GitHub Pages. The native Flutter web target still shows an availability notice.

## Release credentials

Android signing secrets are described in [ANDROID_BUILD.md](ANDROID_BUILD.md).
iOS App Store Connect and signing secrets remain configured in the iOS workflow.
Public Mac archives deliberately use ad-hoc CI signing; Apple Distribution is for App
Store delivery and cannot replace Developer ID notarization. Local Mac builds and tests
use the explicit Brickwright keychain via `scripts/macos_local.py`; never change the
user's default keychain or export its signing identity for a public archive.


Waveform analysis uses native Android/Apple decoders for compressed audio. Windows/Linux
users can install FFmpeg and put it on PATH for compressed-file waveform generation.
PCM WAV analysis needs no external executable. This optional dependency is independent
of normal native playback. Waveform caches contain measured peaks, not audio copies.
Publication compares semantic versions/builds so a slower older build cannot replace
a newer release as latest.

Release staging and publication use lightweight hosted runners; Flutter verification
and platform builds use full build runners. Manual retries use the current workflow
definition and check out the fully qualified existing tag for every build job.
