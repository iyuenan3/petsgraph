#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
version="${PETSGRAPH_VERSION:-1.0.0}"
build_number="${PETSGRAPH_BUILD_NUMBER:-19}"
output_dmg="${PETSGRAPH_OUTPUT_DMG:-$repo_root/.local/dist/builds/PetsGraph-v${version}-macOS-arm64.dmg}"

case "$version" in
  *[!0-9.]*|.*|*.|*..*)
    echo "PETSGRAPH_VERSION must be a numeric semantic version" >&2
    exit 2
    ;;
esac

test "$(printf '%s' "$version" | awk -F. '{print NF}')" = "3"
test "$output_dmg" != "/"
test ! -e "$output_dmg"

stage_root="$(mktemp -d "${TMPDIR:-/tmp}/petsgraph-macos-release.XXXXXX")"
mount_point=""
cleanup() {
  if [ -n "$mount_point" ] && mount | grep -Fq "on $mount_point "; then
    /usr/bin/hdiutil detach "$mount_point" >/dev/null 2>&1 || true
  fi
  rm -rf "$stage_root"
}
trap cleanup EXIT

app_path="$stage_root/PetsGraph.app"
python3 "$repo_root/player/macos/scripts/build-app.py" \
  --output "$app_path" \
  --version "$version" \
  --build-number "$build_number"
ln -s /Applications "$stage_root/Applications"

mkdir -p "$(dirname "$output_dmg")"
/usr/bin/hdiutil create \
  -volname "PetsGraph $version" \
  -srcfolder "$stage_root" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$output_dmg" >/dev/null
/usr/bin/hdiutil verify "$output_dmg" >/dev/null

mount_point="$(mktemp -d "${TMPDIR:-/tmp}/petsgraph-macos-mount.XXXXXX")"
/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$output_dmg" >/dev/null
mounted_app="$mount_point/PetsGraph.app"
test -d "$mounted_app"
test "$(/usr/bin/lipo -archs "$mounted_app/Contents/MacOS/petsgraph")" = "arm64"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mounted_app/Contents/Info.plist")" = "$version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$mounted_app/Contents/Info.plist")" = "$build_number"
test ! -d "$mounted_app/Contents/Resources/Pets"
test -z "$(find "$mounted_app" -name '*.petpack' -print -quit)"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$mounted_app"
/usr/bin/hdiutil detach "$mount_point" >/dev/null
mount_point=""

/usr/bin/shasum -a 256 "$output_dmg"
