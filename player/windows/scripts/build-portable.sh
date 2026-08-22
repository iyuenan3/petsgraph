#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
version="${PETSGRAPH_VERSION:-0.6.0}"
pets_dir="${PETSGRAPH_PETS_DIR:-}"
if [[ -n "$pets_dir" ]]; then
  default_zip="$repo_root/.local/dist/builds/PetsGraph-v${version}-Windows-x64.zip"
else
  default_zip="$repo_root/.local/dist/builds/PetsGraph-v${version}-Windows-x64-runtime.zip"
fi
output_zip="${PETSGRAPH_OUTPUT_ZIP:-$default_zip}"
dotnet_bin="${DOTNET_BIN:-dotnet}"

if ! command -v "$dotnet_bin" >/dev/null 2>&1; then
  dotnet_bin="${HOME}/.dotnet/dotnet"
fi

test -x "$dotnet_bin"
command -v zip >/dev/null 2>&1
test ! -e "$output_zip"

stage_root="$(mktemp -d "${TMPDIR:-/tmp}/petsgraph-windows-package.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT
publish_dir="$stage_root/PetsGraph"

DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-/private/tmp/petsgraph-dotnet-home}" \
  "$dotnet_bin" publish "$repo_root/player/windows/src/PetsGraph.App/PetsGraph.App.csproj" \
  --configuration Release \
  --runtime win-x64 \
  --self-contained true \
  -p:PublishSingleFile=false \
  -p:RestoreLockedMode=true \
  -p:Version="$version" \
  --output "$publish_dir"

cp "$repo_root/player/windows/README-Windows.md" "$publish_dir/README-Windows.md"
printf '%s\n' "$version" > "$publish_dir/VERSION.txt"

if [[ -n "$pets_dir" ]]; then
  test -d "$pets_dir"
  DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-/private/tmp/petsgraph-dotnet-home}" \
    "$dotnet_bin" run --project "$repo_root/player/windows/src/PetsGraph.Validator" -- \
    "$pets_dir" --verify-integrity
  mkdir "$publish_dir/Pets"
  package_count=0
  while IFS= read -r package; do
    package_count=$((package_count + 1))
    if ! cp -cR "$package" "$publish_dir/Pets/$(basename "$package")" 2>/dev/null; then
      cp -R "$package" "$publish_dir/Pets/$(basename "$package")"
    fi
  done < <(find "$pets_dir" -maxdepth 1 -type d -name '*.petsgraph-pet' | sort)
  test "$package_count" -ge 1
fi

mkdir -p "$(dirname "$output_zip")"
(
  cd "$stage_root"
  zip -9 -X -q -r "$output_zip" PetsGraph
)
unzip -tq "$output_zip" >/dev/null
shasum -a 256 "$output_zip"
