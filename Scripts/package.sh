#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/DerivedData/Build/Products/Release/VoiceText.app"
if [ -n "${NOTARY_PROFILE:-}" ] && [ -z "${SIGNING_IDENTITY:-}" ]; then
    echo "公证前必须同时配置 SIGNING_IDENTITY（Developer ID Application）。" >&2
    exit 2
fi
if [ ! -d "$app" ]; then bash Scripts/build.sh; fi
mkdir -p build/Distribution
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$app/Contents/Frameworks/librime.1.dylib"
    codesign --force --timestamp --options runtime --entitlements Resources/VoiceText.entitlements --sign "$SIGNING_IDENTITY" "$app"
fi
codesign --verify --deep --strict "$app"
ditto -c -k --keepParent "$app" build/Distribution/VoiceText.zip
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit build/Distribution/VoiceText.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    ditto -c -k --keepParent "$app" build/Distribution/VoiceText.zip
fi
echo "生成 build/Distribution/VoiceText.zip。未配置 Developer ID 和公证时仅供开发测试。"
