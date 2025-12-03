#!/usr/bin/env bash

# Clean Debian build artifacts in the working tree. Parent-directory outputs are left intact.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pushd "${ROOT_DIR}" >/dev/null

if command -v dh_clean >/dev/null; then
    dh_clean
else
    echo "dh_clean not found; skipping."
fi

echo "Cleaned debian/ build directories (parent artifacts remain)."

popd >/dev/null
