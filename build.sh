#!/bin/bash
set -e

# Find the repository root (where bazarcheck_app folder is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/bazarcheck_app" ]; then
  ROOT_DIR="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../bazarcheck_app" ]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  ROOT_DIR="$(pwd)"
fi

cd "$ROOT_DIR"
echo "=== Working in root: $ROOT_DIR ==="

echo "=== Installing Flutter SDK ==="
if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

export PATH="$PATH:$HOME/flutter/bin"

echo "=== Verifying Flutter ==="
flutter --version

echo "=== Building BazarCheck Web ==="
cd "$ROOT_DIR/bazarcheck_app"
flutter pub get
flutter build web --release

# Copy to ai_service/public in case Vercel is set to the ai_service root
if [ -d "$ROOT_DIR/ai_service" ]; then
  mkdir -p "$ROOT_DIR/ai_service/public"
  cp -r "$ROOT_DIR/bazarcheck_app/build/web/"* "$ROOT_DIR/ai_service/public/" || true
fi

echo "=== Flutter Web Build Complete ==="
