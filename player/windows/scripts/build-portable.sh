#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
version="${PETSGRAPH_VERSION:-0.7.0-dev}"
default_zip="$repo_root/.local/dist/builds/PetsGraph-v${version}-Windows-x64.zip"
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
fixture="$repo_root/petpack/fixtures/synthetic-cat-v1.petpack"

DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-/private/tmp/petsgraph-dotnet-home}" \
  "$dotnet_bin" run --project "$repo_root/player/windows/src/PetsGraph.Validator" \
  --no-restore -p:NuGetAudit=false -- "$fixture"

DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-/private/tmp/petsgraph-dotnet-home}" \
  "$dotnet_bin" publish "$repo_root/player/windows/src/PetsGraph.App/PetsGraph.App.csproj" \
  --configuration Release \
  --runtime win-x64 \
  --self-contained true \
  --no-restore \
  -p:PublishSingleFile=false \
  -p:NuGetAudit=false \
  -p:RestoreLockedMode=true \
  -p:Version="$version" \
  --output "$publish_dir"

cp "$repo_root/player/windows/README-Windows.md" "$publish_dir/README-Windows.md"
printf '%s\n' "$version" > "$publish_dir/VERSION.txt"
test ! -d "$publish_dir/Pets"
test -z "$(find "$publish_dir" -name '*.petpack' -print -quit)"

mkdir -p "$(dirname "$output_zip")"
(
  cd "$stage_root"
  zip -9 -X -q -r "$output_zip" PetsGraph
)
unzip -tq "$output_zip" >/dev/null
shasum -a 256 "$output_zip"
