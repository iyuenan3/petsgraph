#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source_png="$repo_root/assets/brand/petsgraph-logo.png"
iconset_dir="$repo_root/assets/brand/macos/PetsGraph.iconset"
dotnet_bin="${DOTNET_BIN:-dotnet}"

if ! command -v "$dotnet_bin" >/dev/null 2>&1; then
  dotnet_bin="${HOME}/.dotnet/dotnet"
fi

test -f "$source_png"
test -x "$dotnet_bin"
command -v sips >/dev/null 2>&1

mkdir -p "$iconset_dir" "$repo_root/assets/brand/macos" "$repo_root/assets/brand/windows"

sips -z 16 16 "$source_png" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$source_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$source_png" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$source_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$source_png" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$source_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$source_png" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$source_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$source_png" --out "$iconset_dir/icon_512x512.png" >/dev/null
cp "$source_png" "$iconset_dir/icon_512x512@2x.png"

DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-/private/tmp/petsgraph-dotnet-home}" \
  "$dotnet_bin" run --project "$repo_root/assets/brand/tools/PetsGraph.IconPacker" -- \
  icns "$iconset_dir" "$repo_root/assets/brand/macos/PetsGraph.icns"
DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-/private/tmp/petsgraph-dotnet-home}" \
  "$dotnet_bin" run --project "$repo_root/assets/brand/tools/PetsGraph.IconPacker" -- \
  ico "$iconset_dir" "$repo_root/assets/brand/windows/PetsGraph.ico"
sips -z 256 256 "$source_png" --out "$repo_root/assets/brand/windows/PetsGraph.png" >/dev/null
