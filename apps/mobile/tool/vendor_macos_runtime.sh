#!/usr/bin/env bash
# Fetches the engine the macOS build bundles, from its official release,
# checked against a pinned SHA-256: the Xray version Linux and Windows ship,
# for Apple silicon and Intel, joined into one universal binary. Runs on
# macOS (lipo). A mismatch stops the build.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$root/assets/macos_runtime"
xray_version='v26.11.9'
xray_arm64_hash='233f0c66681cd0726f81a6b2b6ed6a5710869e312047b522e46ed53035bebd26'
xray_amd64_hash='488963e676e06f5e48547f9dd38116aaca8de4234959b4272ae8f284e658dfd0'

mkdir -p "$destination"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

fetch() { # url, file, expected sha256
  curl -fsSL --retry 3 -o "$2" "$1"
  local actual
  actual="$(shasum -a 256 "$2" | cut -d' ' -f1)"
  if [ "$actual" != "$3" ]; then
    echo "SHA-256 mismatch for $(basename "$2"): expected $3, got $actual" >&2
    exit 1
  fi
}

base="https://github.com/XTLS/Xray-core/releases/download/$xray_version"
fetch "$base/Xray-macos-arm64-v8a.zip" "$temporary/arm64.zip" "$xray_arm64_hash"
fetch "$base/Xray-macos-64.zip" "$temporary/amd64.zip" "$xray_amd64_hash"
unzip -qo "$temporary/arm64.zip" xray geoip.dat geosite.dat LICENSE -d "$temporary/arm64"
unzip -qo "$temporary/amd64.zip" xray -d "$temporary/amd64"
lipo -create "$temporary/arm64/xray" "$temporary/amd64/xray" -output "$destination/xray"
mv "$temporary/arm64/geoip.dat" "$temporary/arm64/geosite.dat" "$temporary/arm64/LICENSE" "$destination/"
# Its routing data, cut to what the app names (26 MB of every country).
python3 "$root/tool/trim_geodata.py" "$destination"
chmod 755 "$destination/xray"
echo "macOS runtime ready: $(ls "$destination" | tr '\n' ' ')"
