#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
developer_dir=/Applications/Xcode.app/Contents/Developer

if [ ! -d "${developer_dir}" ]; then
  echo "petsgraph tests require the full Xcode toolchain at ${developer_dir}" >&2
  exit 2
fi

export DEVELOPER_DIR="${developer_dir}"
export SWIFTPM_MODULECACHE_OVERRIDE="${project_root}/.build/ModuleCache-Xcode"
export CLANG_MODULE_CACHE_PATH="${project_root}/.build/ModuleCache-Xcode"

mkdir -p "${SWIFTPM_MODULECACHE_OVERRIDE}"
exec xcrun swift test --package-path "${project_root}" --disable-sandbox "$@"
