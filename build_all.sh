#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "CrisperPlayer build_all"
/home/claudeuser/flutter/bin/flutter pub get
/home/claudeuser/flutter/bin/dart run build_runner build --delete-conflicting-outputs || /home/claudeuser/flutter/bin/dart run build_runner build
/home/claudeuser/flutter/bin/flutter build web --no-wasm-dry-run
echo "web done: build/web"
if [ -n "$ANDROID_HOME" ]; then
  /home/claudeuser/flutter/bin/flutter build apk --release
  echo "apk done"
else
  echo "ANDROID_HOME not set, skipping apk"
fi
