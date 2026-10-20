#!/bin/bash
set -e

echo "=== Installing Flutter SDK ==="
if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

export PATH="$PATH:$HOME/flutter/bin"

echo "=== Verifying Flutter ==="
flutter --version

echo "=== Building BazarCheck Web ==="
cd bazarcheck_app
flutter pub get
flutter build web --release

echo "=== Flutter Web Build Complete ==="
