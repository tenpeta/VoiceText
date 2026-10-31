#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
swift test --disable-sandbox --scratch-path build/SwiftPM --cache-path build/PackageCache \
    --config-path build/PackageConfig --security-path build/PackageSecurity
if [ ! -f Vendor/.bootstrap-complete ] || [ ! -f Vendor/lib/librime.1.dylib ]; then python3 Scripts/bootstrap.py; fi
python3 Scripts/prepare_resources.py
mkdir -p build/RimeSmoke/User build/RimeSmoke/Logs
xcrun clang -std=gnu11 -I RimeBridge -I Vendor/include RimeBridge/RimeBridge.c Tests/RimeSmoke.c \
    -L Vendor/lib -lrime -Wl,-rpath,"$PWD/Vendor/lib" -o build/RimeSmoke/rime-smoke
build/RimeSmoke/rime-smoke "$PWD/build/RimeShared" "$PWD/build/RimeSmoke/User" "$PWD/build/RimeSmoke/Logs"
