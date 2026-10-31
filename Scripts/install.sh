#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-build/DerivedData/Build/Products/Release/VoiceText.app}"
codesign --verify --deep --strict "$app"
swift Scripts/install.swift "$app"
open "$HOME/Library/Input Methods/VoiceText.app"
