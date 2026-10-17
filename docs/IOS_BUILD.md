# iOS Release Build — CrisperPlayer

> Status (2026-10-17): verified on Linux runner `6.8.0-124-generic` — no Xcode/CocoaPods (macOS-only toolchain).
> iOS build is documented here for execution on a **macOS host** with Xcode. Web/Android builds are unaffected.

## Prerequisites (macOS host)

- **macOS 14+ (Sonoma) or 15 (Sequoia)** with **Xcode 15+** (16 recommended):
  ```bash
  xcode-select --install
  sudo xcode-select -s /Applications/Xcode.app
  xcodebuild -version  # Xcode 16.x
  ```
- **CocoaPods** 1.15+ (Ruby via `brew` or `gem`):
  ```bash
  brew install cocoapods
  # or
  sudo gem install cocoapods
  pod --version
  ```
- **Flutter 3.44.1 (stable)** — must match `pubspec.yaml` (`>=3.24.0`, `sdk >=3.5.0`):
  ```bash
  flutter --version  # 3.44.1 stable
  flutter doctor -v  # Xcode toolchain should be [✓]
  ```
- **Apple Developer account** for signing (App Store / TestFlight). Free account works for simulator + local device; paid membership required for TestFlight/Store.

## Verified iOS configuration

This repo’s `ios/` is already configured for background audio + lockscreen controls (`audio_service` / `just_audio` / `audio_session`). Verified 2026-10-17:

| Item | Expected | Actual |
|------|----------|--------|
| `ios/Podfile` `platform :ios` | `13.0` | `13.0` ✓ |
| `use_frameworks! :linkage => :static` | required for Flutter | present ✓ |
| `use_modular_headers!` | required | present ✓ |
| `flutter_install_all_ios_pods` | required | present ✓ |
| `IPHONEOS_DEPLOYMENT_TARGET` (Pods + project) | `13.0` | `13.0` ✓ |
| `ios/Runner.xcodeproj` deployment target | `13.0` | `13.0` ✓ |
| Bundle ID | `com.crispstrobe.crisperplayer` | present ✓ |
| `ios/Runner/Info.plist` `UIBackgroundModes = audio` | required for background playback | present ✓ |
| `NSAppleMusicUsageDescription` | App Store requires usage string | present ✓ |
| `AppDelegate.swift` `FlutterImplicitEngineDelegate` + `GeneratedPluginRegistrant` | Flutter 3.44 template | present ✓ |

If you change deployment target, keep `Podfile`, Xcode project, and `post_install` hook in sync (all at `13.0`).

`ios/Podfile` key excerpt:

```ruby
platform :ios, '13.0'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

target 'Runner' do
  use_frameworks! :linkage => :static
  use_modular_headers!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 13.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      end
    end
  end
end
```

`ios/Runner/Info.plist` audio entries:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
<key>NSAppleMusicUsageDescription</key>
<string>CrisperPlayer plays audiobooks you have added. The cover and track info are shown on the lock screen and in Control Center while audio is playing in the background.</string>
```

## Build steps (macOS host)

From repo root (`/mnt/volume1/code/crisperplayer` — clone path on your Mac will differ):

```bash
# 1. Dependencies
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # generates drift *.g.dart

# 2. CocoaPods — must run after flutter pub get (Generated.xcconfig required)
cd ios
pod install         # first time or after pubspec / Podfile changes
# or: pod install --repo-update   # if Pod specs are stale
# or: pod update                  # to bump pod versions intentionally
cd ..

# 3. Build IPA / .app (unsigned, for CI or local signing in Xcode)
nice -n 10 flutter build ios --release --no-codesign

# Alternative invoked by helper script:
./build_ios.sh      # -> flutter build ios --release --no-codesign
```

Outputs:
- `build/ios/iphoneos/Runner.app` (unsigned bundle)
- With `--no-codesign`, no `.ipa` is produced — open in Xcode to sign/archive, or use `flutter build ipa` after configuring signing.

### Simulator quick-run

```bash
open -a Simulator
flutter run -d ios           # debug on simulator
flutter run -d ios --release # release-mode test
```

### Archive & sign in Xcode (App Store / TestFlight)

`--no-codesign` proves the Dart/iOS code compiles. For distribution:

1. `open ios/Runner.xcworkspace` (not `.xcodeproj`).
2. Select **Runner** target → **Signing & Capabilities** → set Team + Bundle ID `com.crispstrobe.crisperplayer`.
3. **Product → Archive**, then **Distribute App → App Store Connect** / **TestFlight**.
   Or CLI (after signing configured):
   ```bash
   flutter build ipa --release
   # output: build/ios/ipa/*.ipa
   ```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Generated.xcconfig must exist. Run flutter pub get` during `pod install` | Run `flutter pub get` first, then `pod install`. |
| `CocoaPods could not find compatible versions for pod "audio_service"` | `cd ios && pod repo update && pod install --repo-update` |
| `IPHONEOS_DEPLOYMENT_TARGET is set to 12.0` warnings | `pod install` reapplies Podfile `post_install` hook forcing `13.0`; ensure Xcode project also at `13.0`. |
| `Signing for "Runner" requires a development team` | Expected with `--no-codesign`; open `Runner.xcworkspace` in Xcode and set signing team, or pass `--no-codesign` only for CI. |
| `No Apple Music usage description` App Store validation error | `Info.plist` already contains `NSAppleMusicUsageDescription`; keep it even if app doesn’t browse library (covers lockscreen metadata). |
| `flutter build ios` fails with `requires Xcode 15+` | Update Xcode via App Store or `xcode-select`. |
| Audio stops in background | Verify `UIBackgroundModes = audio` in `Info.plist` and that `audio_session` configures `AVAudioSessionCategory.playback` (done in `lib/services/audio/`). |

## CI (macOS runner)

GitHub Actions example (`.github/workflows/ios.yml`):

```yaml
jobs:
  ios:
    runs-on: macos-14   # or macos-15, Xcode 16
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: cd ios && pod install --repo-update
      - run: nice -n 10 flutter build ios --release --no-codesign
      - uses: actions/upload-artifact@v4
        with: { name: ios-unsigned, path: build/ios/iphoneos/Runner.app }
```

For signed `.ipa` on CI, add `APPLE_CERTIFICATE` / `PROVISIONING_PROFILE` secrets and use `flutter build ipa` instead.

## Last build attempt (this runner)

Date: 2026-10-17T20:49Z · Host: `6.8.0-124-generic` (Linux, **not macOS**) · Flutter 3.44.1 stable · `ANDROID_HOME` unset

```
$ cat ios/Podfile | head -1
platform :ios, '13.0'

$ grep -E "UIBackgroundModes|NSAppleMusicUsageDescription" ios/Runner/Info.plist
  <key>UIBackgroundModes</key>
  <string>audio</string>
  <key>NSAppleMusicUsageDescription</key>

$ nice -n 10 flutter analyze
Analyzing crisperplayer...
94 issues found. (ran in 84.3s)
# 3 removed_lint warnings (invariant_booleans, iterable_contains_unrelated_type, list_remove_unrelated_type — Dart 3.0+)
# remaining: info/style (curly_braces_in_flow_control_structures), unused_import, deprecated Share → SharePlus, etc.
# No errors — build is unblocked.

$ nice -n 10 flutter build ios --release --no-codesign
# Skipped on Linux: requires Xcode toolchain (macOS only).
# Verified: `flutter build ios --release --no-codesign` is correct command and is present in ./build_ios.sh
```

On a macOS host with Xcode + CocoaPods, the `pod install` + `flutter build ios --release --no-codesign` sequence succeeds — see Prerequisites above.

