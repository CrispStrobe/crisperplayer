#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
flutter pub get
dart run build_runner build --build-filter lib/services/db/app_database.g.dart
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-wasm-dry-run --no-pub
if [[ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]]; then
  flutter build apk --release --no-pub
fi
