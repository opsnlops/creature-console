#!/usr/bin/env bash

# The amd64 Debian packages and nothing else, for an amd64 machine: the same build as CI and
# build_debs.sh (Debian Trixie image, pinned Swift, dpkg-buildpackage), natively, with no
# install smoke test afterwards. The packages land in artifacts/amd64/.
#
# Usage (from a checkout on the amd64 host):
#   ./build_debs_express.sh            # amd64 packages
#   ./build_debs_express.sh --clean    # discard the build cache first (a cold build)
#   ./build_debs_express.sh --out /path

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "build_debs_express.sh builds amd64 natively; this machine is $(uname -m)." >&2
    echo "Use ./build_debs.sh --arch amd64 to build it under emulation." >&2
    exit 1
fi

exec "${ROOT_DIR}/build_debs.sh" --arch amd64 --no-check "$@"
