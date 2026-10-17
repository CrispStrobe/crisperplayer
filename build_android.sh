#!/bin/bash
set -e
cd "$(dirname "$0")"
/home/claudeuser/flutter/bin/flutter build apk --release
