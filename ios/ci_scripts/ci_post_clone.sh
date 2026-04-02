#!/bin/sh
set -e

# Install Homebrew if not present
if ! command -v brew &> /dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install Flutter via homebrew or download directly
FLUTTER_VERSION="3.29.2"
FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Downloading Flutter $FLUTTER_VERSION..."
  curl -fsSLo /tmp/flutter.zip "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_${FLUTTER_VERSION}-stable.zip"
  unzip -q /tmp/flutter.zip -d "$HOME"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

echo "Flutter version:"
flutter --version

# Go to project root (one level up from ios/ci_scripts)
cd "$CI_WORKSPACE"

echo "Running flutter pub get..."
flutter pub get

echo "Running pod install..."
cd ios
pod install --repo-update

echo "Done."
