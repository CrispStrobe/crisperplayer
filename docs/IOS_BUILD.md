# iOS builds and internal TestFlight

Use Flutter 3.44.4, Dart 3.12 and iOS 15+. The project uses CocoaPods only; Swift Package Manager is disabled in pubspec and CI to avoid duplicate plugin linkage. The host and share extension both use App Group `group.com.crispstrobe.crisperplayer`.

## GitHub Actions

The CI workflow checks analysis, Dart tests, release helper tests, Android APK generation and the iOS simulator build. It saves the APK and simulator app as artifacts.

`ios-release.yml` archives unsigned, then signs at export with the existing canonical Apple Distribution certificate `L9PHHNLY9Y`. It explicitly restores the authorized App Group entitlement after export, re-signing the extension before its host with that same identity. Unsigned archives otherwise lose this custom entitlement during export. It never enables automatic provisioning or creates/revokes certificates. A `v*` tag uploads; manual dispatch defaults to `dry_run: true` and saves the signed IPA without uploading.

The exported IPA is checked for the exact bundle identifiers, marketing/build versions, minimum iOS version, export-compliance declaration, signatures, profiles and App Group entitlements in BOTH the host and extension. TestFlight delivery waits for the exact iOS platform/version/build, creates beta metadata in the primary locale, assigns an internal group and verifies `IN_BETA_TESTING`. It does not submit external Beta App Review or an App Store release.

Required repository secrets:

- `ASC_API_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_TEAM_ID`, `ASC_APP_ID`
- `DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD` for the shared canonical certificate
- `IOS_PROFILE_APP_BASE64`, `IOS_PROFILE_EXT_BASE64` for the two explicit App Store profiles
- `ASC_INTERNAL_TESTER_EMAIL` for an existing App Store Connect team member

The app ID is verified against `com.crispstrobe.crisperplayer` before upload. A wrong numeric app ID is never used as a fallback.

## First release setup

Follow the account protocol in `../appstore.md`:

1. Register `com.crispstrobe.crisperplayer` and `com.crispstrobe.crisperplayer.ShareExtension`.
2. Enable App Groups on both new identifiers. Do not change another app's capabilities or profiles.
3. In the Developer portal, create `group.com.crispstrobe.crisperplayer` and assign it to BOTH identifiers. Group assignment is browser-only.
4. In App Store Connect, create the iOS app record using the host bundle ID. App record creation is browser-only.
5. Create both explicit `IOS_APP_STORE` profiles against the canonical certificate AFTER group assignment; verify their group entitlement before configuring the profile secrets.
6. Resolve the numeric app ID from the API, set `ASC_APP_ID`, bump the build number and push a release tag after CI passes.

Signing keys, profiles and passwords must stay outside git. Internal TestFlight does not require an App Store privacy label or external Beta App Review. Testers use the TestFlight app signed in with their existing App Store Connect Apple ID.

## Local checks

```sh
flutter pub get
flutter config --no-enable-swift-package-manager
flutter analyze --no-pub
flutter test --no-pub
flutter build ios --simulator --debug --no-codesign
```

For CocoaPods on this Mac, clear incompatible Ruby overrides:

```sh
env -u GEM_HOME -u GEM_PATH -u RUBYOPT pod install --project-directory=ios
```

The local SDK/cache tools can stall on this machine. CI is the binary-build verification path; do not treat a stalled local attempt as a successful build.

The host, share extension and CocoaPods deployment targets are all iOS 15.0 or newer. IPA verification rejects a lower minimum or missing document-opening configuration. `LSSupportsOpeningDocumentsInPlace` is explicitly false because imports copy audio into app-owned storage.
