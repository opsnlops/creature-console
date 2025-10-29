#!/usr/bin/env bash

# Build script for creature-cli release version
# Works on both macOS and Linux and copies the built binary into cli/

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="${ROOT_DIR}/cli"
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

echo "Building creature-cli release version..."
pushd "${COMMON_DIR}" >/dev/null
echo "Cleaning previous build artifacts..."
swift package clean

BUILD_FLAGS=(-c release --product creature-cli)
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

mkdir -p "${CLI_DIR}"

cp "${BIN_DIR}/creature-cli" "${CLI_DIR}/"
echo "creature-cli copied to ${CLI_DIR}/creature-cli"
echo "✅ Release build complete!"
