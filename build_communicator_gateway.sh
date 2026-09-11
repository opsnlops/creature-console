#!/usr/bin/env bash

# Build script for the Creature Communicator Gateway release version.
# Works on both macOS and Linux and copies the built binary into communicator-gateway/.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="${ROOT_DIR}/communicator-gateway"
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

echo "Building creature-communicator-gateway release version..."
pushd "${COMMON_DIR}" >/dev/null
echo "Cleaning previous build artifacts..."
swift package clean

BUILD_FLAGS=(-c release --product creature-communicator-gateway)
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

mkdir -p "${GATEWAY_DIR}"

STAGED_BINARY="$(mktemp "${GATEWAY_DIR}/.creature-communicator-gateway.XXXXXX")"
trap 'rm -f "${STAGED_BINARY}"' EXIT
install -m 755 "${BIN_DIR}/creature-communicator-gateway" "${STAGED_BINARY}"
mv -f "${STAGED_BINARY}" "${GATEWAY_DIR}/creature-communicator-gateway"
trap - EXIT
echo "creature-communicator-gateway copied to ${GATEWAY_DIR}/creature-communicator-gateway"
echo "✅ Release build complete!"
