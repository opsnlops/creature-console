#!/usr/bin/env bash

# Build the Debian package using existing debian/ metadata.
# This script assumes debian/control, debian/rules, and debian/changelog are maintained.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pushd "${ROOT_DIR}" >/dev/null

if ! command -v dpkg-buildpackage >/dev/null; then
    echo "dpkg-buildpackage not found. Install dpkg-dev/debhelper first." >&2
    exit 1
fi

dpkg-buildpackage -us -uc -b

echo "Built Debian package(s) in parent directory:"
ls -1 ../creature-cli_* || true

popd >/dev/null
