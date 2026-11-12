#!/usr/bin/env bash
# Run every SMB test layer locally:
#   1. unit tests (whole Flutter suite; live tests skip without servers)
#   2. mock server: impacket SMB2 fixture (test/smb_live_test.dart, plus the
#      paramiko SFTP fixture) once per engine: libsmb2, rust, auto
#   3. real server: live SMB3 qualification (signing + encryption required)
#      on the host, and optionally in the macOS app and an iOS simulator app
#      with the bridge bundled by the build hook
#
# Environment:
#   SMB_TEST_PYTHON     Python with impacket==0.13.0 and paramiko (mock layer)
#   CRISPER_SMB3_URL    e.g. smb://127.0.0.1:1445/Books/ (real layer; see the
#                       header of test/smb3_backend_qualification_test.dart
#                       for the optional PLAIN/DENIED/BIG_SHA256 variables)
#   SMB_APPS            space-separated devices for the app runs, e.g.
#                       "macos <simulator-udid>" (optional)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
step() { printf '\n=== %s\n' "$*"; }

step "pub get + analyze"
flutter pub get >/dev/null
flutter analyze --no-pub

step "unit tests"
flutter test --no-pub

if [[ -n "${SMB_TEST_PYTHON:-}" ]]; then
  for engine in libsmb2 rust auto; do
    step "mock server (impacket SMB2 + paramiko SFTP), engine=$engine"
    CRISPER_SMB_PYTHON="$SMB_TEST_PYTHON" CRISPER_SFTP_PYTHON="$SMB_TEST_PYTHON" \
      flutter test --no-pub --dart-define=CRISP_SMB_BACKEND="$engine" \
      test/smb_live_test.dart test/sftp_live_test.dart
  done
else
  echo "SMB_TEST_PYTHON not set: skipping the mock-server layer"
fi

if [[ -n "${CRISPER_SMB3_URL:-}" ]]; then
  step "real SMB3 server, host (bridge from build/native_assets)"
  flutter test --no-pub test/smb3_backend_qualification_test.dart
  defines=()
  for key in CRISPER_SMB3_URL CRISPER_SMB3_USER CRISPER_SMB3_SECRET \
             CRISPER_SMB3_BIG_SHA256 CRISPER_SMB3_PLAIN_URL \
             CRISPER_SMB3_DENIED_URL CRISPER_SMB3_BACKENDS; do
    [[ -n "${!key:-}" ]] && defines+=("--dart-define=$key=${!key}")
  done
  for device in ${SMB_APPS:-}; do
    step "real SMB3 server, app on $device (bundled bridge)"
    env -u CRISP_SMB_LIBRARY flutter test \
      integration_test/smb3_backend_qualification_test.dart -d "$device" \
      "${defines[@]}" --dart-define=CRISPER_SMB3_EXPECT_BUNDLED=true
  done
else
  echo "CRISPER_SMB3_URL not set: skipping the real-server layer"
fi
step "all requested SMB layers passed"
