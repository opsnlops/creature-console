#!/usr/bin/env bash
#
# Build every Debian package from this repository, inside the Dockerfile.debian image.
#
#   scripts/dpkg-build-in-container.sh <source-dir> <out-dir>
#
# The one build recipe shared by .github/workflows/build-deb.yml and build_debs.sh, so CI and a
# local build cannot drift. Packages are built on Debian (trixie), never on Ubuntu, per the fleet
# packaging policy. dpkg-buildpackage writes into the parent of <source-dir>; the .deb and .ddeb
# files for this architecture are copied to <out-dir>.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <source-dir> <out-dir>" >&2
    exit 2
fi

source_dir="$(cd "$1" && pwd)"
out_dir="$2"
arch="$(dpkg --print-architecture)"
parent="$(dirname "${source_dir}")"

mkdir -p "${out_dir}"
rm -f "${parent}"/*.deb "${parent}"/*.ddeb "${parent}"/*.changes "${parent}"/*.buildinfo

cd "${source_dir}"
swift --version
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -us -uc -b

# Debian names debug-symbol packages *-dbgsym_*.deb; Ubuntu uses .ddeb. Take both.
find "${parent}" -maxdepth 1 \( -name "*_${arch}.deb" -o -name "*_${arch}.ddeb" \) \
    -exec cp {} "${out_dir}/" \;
