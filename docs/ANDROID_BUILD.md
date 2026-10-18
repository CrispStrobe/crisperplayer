# Android builds

CI uses Flutter 3.44.4 and Java 17. Install Android Studio/SDK, accept the SDK licenses,
and check `flutter doctor -v` before local builds. Flutter chooses compile/target/min SDK
from its SDK defaults; do not lower these to work around missing local SDK packages.

```sh
flutter pub get
flutter build apk --release
# Optional Play Console artifact, not part of the GitHub release:
flutter build appbundle --release
```

The APK is `build/app/outputs/flutter-apk/app-release.apk`.
AAB output is `build/app/outputs/bundle/release/app-release.aab`.

## Signing

Local builds without signing environment variables use the debug key for convenience.
Public releases use a dedicated persistent PKCS12 keystore and all four variables:

- `CRISPER_ANDROID_KEYSTORE`: absolute keystore path
- `CRISPER_ANDROID_STORE_PASSWORD`
- `CRISPER_ANDROID_KEY_ALIAS`
- `CRISPER_ANDROID_KEY_PASSWORD`

Partial configuration fails rather than silently falling back. Keep passwords out of
command history and logs. On the maintainer Mac, the keystore is in
`~/.config/crisperplayer/signing/android-release.p12`; its password is the generic
password item with service `com.crispstrobe.crisperplayer.release` and account
`crisperplayer-android-release` in the explicit Brickwright keychain. Back up that
keystore and credential securely: losing the key prevents compatible APK updates.

The release workflow restores the key from `ANDROID_KEYSTORE_BASE64`,
`ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` GitHub secrets.
It verifies the finished APK signature, rejects Android Debug certificates, and publishes
the public certificate details in `ANDROID-SIGNING.txt` beside the APK.
The public certificate SHA-256 is
`ee29c86a1d3210bef3d9888afcef623f23690527d474239a250e97d21f819c0a`.

Earlier CI artifacts used debug keys and cannot be updated in place with this release key.
Export library metadata and retain original audio before replacing such an installation;
uninstalling removes managed app data. Future public release APKs use the persistent key.

## CI and downloads

Regular `ci.yml` APKs are temporary developer artifacts and use the debug key.
`release.yml` publishes signed APKs to a versioned GitHub release after all checks pass.
Use the [release procedure](RELEASES.md), not a manually uploaded standalone APK.
The native Android player and audio effects still need physical-device validation;
compilation and unit tests do not establish Bluetooth/background behavior.
