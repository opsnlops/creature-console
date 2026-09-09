#!/usr/bin/env bash

# Build script for creature-world release version
# Works on both macOS and Linux and copies the built binary into world/

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLD_DIR="${ROOT_DIR}/world"
COMMON_DIR="${ROOT_DIR}/Common"

STATIC_STDLIB=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --static-swift-stdlib|--static)
            STATIC_STDLIB=true
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--static]" >&2
            exit 1
            ;;
    esac
    shift
done

echo "Building creature-world release version..."
pushd "${COMMON_DIR}" >/dev/null
echo "Cleaning previous build artifacts..."
swift package clean

BUILD_FLAGS=(-c release --product creature-world)
if [[ "${STATIC_STDLIB}" == "true" ]]; then
    if [[ "$(uname -s)" == "Linux" ]]; then
        BUILD_FLAGS+=(--static-swift-stdlib)
        echo "Enabling static Swift standard library for Linux build."
    else
        echo "Static Swift standard library is only supported on Linux. Ignoring --static flag."
    fi
fi

swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
popd >/dev/null

echo "Build completed successfully!"

mkdir -p "${WORLD_DIR}"

STAGED_BINARY="$(mktemp "${WORLD_DIR}/.creature-world.XXXXXX")"
trap 'rm -f "${STAGED_BINARY}"' EXIT
install -m 755 "${BIN_DIR}/creature-world" "${STAGED_BINARY}"
mv -f "${STAGED_BINARY}" "${WORLD_DIR}/creature-world"
trap - EXIT
echo "creature-world copied to ${WORLD_DIR}/creature-world"
echo "✅ Release build complete!"
