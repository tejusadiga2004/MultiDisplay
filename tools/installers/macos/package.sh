#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)[[:space:]]*$/\1-build.\2/p' "$root/pubspec.yaml")"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-build\.[0-9]+$ ]]; then
  echo "Installer packaging requires pubspec version: major.minor.patch+build" >&2
  exit 1
fi
app="$root/build/macos/Build/Products/Release/Multi Display.app"
output="$root/build/installers/macos"
base="Multi-Display-$version-macos-universal"

for file in \
  "Contents/Info.plist" \
  "Contents/MacOS/Multi Display" \
  "Contents/Resources/AppIcon.icns" \
  "Contents/Resources/display_capture_display_capture.bundle/Contents/Resources/default.metallib"; do
  if [ ! -f "$app/$file" ]; then
    echo "Missing build output: $file" >&2
    exit 1
  fi
done
for arch in arm64 x86_64; do
  lipo "$app/Contents/MacOS/Multi Display" -verify_arch "$arch"
done

mkdir -p "$output"
stage="$(mktemp -d "${TMPDIR:-/tmp}/multi-display-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Multi Display.app"
ln -s /Applications "$stage/Applications"
cp "$root/tools/installers/macos/INSTALL.txt" "$stage/INSTALL.txt"
hdiutil create -volname "Multi Display" -srcfolder "$stage" \
  -format UDZO -ov "$output/$base.dmg"
hdiutil verify "$output/$base.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$base-portable.zip"
unzip -tq "$output/$base-portable.zip"
(
  cd "$output"
  shasum -a 256 "$base.dmg" "$base-portable.zip" > "$base-SHA256SUMS.txt"
)
