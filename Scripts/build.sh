#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f Vendor/.bootstrap-complete ] || [ ! -f Vendor/lib/librime.1.dylib ] || [ ! -f Resources/Rime/upstream/essay.txt ]; then
    python3 Scripts/bootstrap.py
fi
python3 Scripts/generate_project.py
python3 Scripts/prepare_resources.py
if [ ! -f Resources/InputSourceIcon.pdf ] || [ ! -f Resources/AppIcon.icns ] || [ Scripts/create-icon.swift -nt Resources/AppIcon.icns ]; then
    swift Scripts/create-icon.swift "$PWD"
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
xcodebuild -project VoiceText.xcodeproj -scheme VoiceText -configuration "${CONFIGURATION:-Release}" \
    -derivedDataPath build/DerivedData build "$@"
