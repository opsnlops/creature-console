#!/usr/bin/env bash

# Build the amd64 and arm64 Debian packages locally, exactly as CI does, and drop them in
# artifacts/ so a deploy never has to wait for GitHub Actions.
#
# This is .github/workflows/build-deb.yml run by hand: the same Debian Trixie base and apt
# packages, the same pinned Swift release, the same dpkg-buildpackage invocation and build flags,
# and the same clean-container install, --version, --help, and ldd smoke test. The only
# difference is where the toolchain runs: the workflow's Swiftly step runs on an Ubuntu runner,
# while this builds on Debian Trixie itself with swift.org's Debian toolchain tarball.
#
# Each architecture builds inside the repository's own Debian Trixie image (Dockerfile.debian)
# with a persistent, per-architecture build volume, so the first run is a cold Swift release
# build and later runs are incremental. The working tree — including uncommitted changes — is
# synchronized into that volume; the host checkout and Common/.build are never written to.
#
# Usage:
#   ./build_debs.sh                       # both architectures, packages + install smoke test
#   ./build_debs.sh --arch arm64          # one architecture (native on Apple silicon)
#   ./build_debs.sh --no-check            # skip the clean-container install smoke test
#   ./build_debs.sh --clean               # discard the build volumes first (forces a cold build)
#   ./build_debs.sh --out /path           # artifact directory (default: ./artifacts)
#
# The non-native architecture runs under Docker's emulation and is several times slower than the
# native one; a cold amd64 build on Apple silicon can take well over an hour, so build the native
# architecture first when iterating and let the persistent cache make the other one tolerable.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_VERSION="${SWIFT_VERSION:-$(sed -n 's/^ARG SWIFT_VERSION=\(.*\)$/\1/p' "${ROOT_DIR}/Dockerfile.debian")}"
IMAGE_PREFIX="creature-console-deb-builder"
VOLUME_PREFIX="creature-console-deb-work"
PRODUCTS=(creature-cli creature-mqtt creature-agent creature-world creature-communicator-gateway)

ARCHES=(amd64 arm64)
OUT_DIR="${ROOT_DIR}/artifacts"
RUN_CHECK=1
CLEAN=0

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            IFS=',' read -r -a ARCHES <<<"$2"
            shift 2
            ;;
        --out)
            OUT_DIR="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
            shift 2
            ;;
        --no-check) RUN_CHECK=0; shift ;;
        --clean) CLEAN=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for arch in "${ARCHES[@]}"; do
    case "${arch}" in
        amd64 | arm64) ;;
        *)
            echo "Unsupported architecture '${arch}'; expected amd64 or arm64." >&2
            exit 2
            ;;
    esac
done

if ! command -v docker >/dev/null; then
    echo "docker not found; install Docker Desktop first." >&2
    exit 1
fi

mkdir -p "${OUT_DIR}"

log() {
    printf '\n\033[1;35m==> %s\033[0m\n' "$*" >&2
}

build_image() {
    local arch="$1"
    local image="${IMAGE_PREFIX}:swift-${SWIFT_VERSION}-${arch}"
    log "Preparing ${image} (linux/${arch})"
    docker build \
        --platform "linux/${arch}" \
        --build-arg "SWIFT_VERSION=${SWIFT_VERSION}" \
        -t "${image}" \
        -f "${ROOT_DIR}/Dockerfile.debian" \
        "${ROOT_DIR}" >/dev/null
    echo "${image}"
}

build_packages() {
    local arch="$1"
    local image="$2"
    local volume="${VOLUME_PREFIX}-${arch}"

    if [[ "${CLEAN}" -eq 1 ]]; then
        log "Discarding build cache ${volume}"
        docker volume rm -f "${volume}" >/dev/null 2>&1 || true
    fi
    docker volume create "${volume}" >/dev/null

    log "Building Debian packages for ${arch} (cache: ${volume})"
    docker run --rm \
        --platform "linux/${arch}" \
        -v "${ROOT_DIR}:/source:ro" \
        -v "${volume}:/work" \
        -v "${OUT_DIR}:/out" \
        -e "ARCH=${arch}" \
        "${image}" bash -c '
            set -euo pipefail
            mkdir -p /work/creature-console
            # Excluded paths are protected from --delete, so the Swift build cache survives.
            rsync -a --delete \
                --exclude .git --exclude .build --exclude artifacts \
                --exclude "*.xcodeproj" --exclude "DerivedData" \
                --exclude "debian/creature-*/" --exclude "debian/.debhelper" \
                --exclude "debian/*.debhelper*" --exclude "debian/files" \
                --exclude "debian/*.substvars" --exclude "debian/tmp" \
                /source/ /work/creature-console/
            rm -f /work/*.deb /work/*.ddeb /work/*.changes /work/*.buildinfo
            cd /work/creature-console
            swift --version
            # Identical to the "Build Debian package" step in .github/workflows/build-deb.yml.
            export DEB_BUILD_OPTIONS=nocheck
            SWIFT_BUILD_FLAGS="-c release --product creature-cli --static-swift-stdlib" \
            SWIFT_BUILD_FLAGS_MQTT="-c release --product creature-mqtt --static-swift-stdlib" \
            SWIFT_BUILD_FLAGS_WORLD="-c release --product creature-world --static-swift-stdlib" \
            SWIFT_BUILD_FLAGS_COMMUNICATOR_GATEWAY="-c release --product creature-communicator-gateway --static-swift-stdlib" \
                dpkg-buildpackage -us -uc -b
            # Debian names debug-symbol packages *-dbgsym_*.deb; Ubuntu uses .ddeb. Take both.
            find /work -maxdepth 1 \( -name "*_${ARCH}.deb" -o -name "*_${ARCH}.ddeb" \) \
                -exec cp {} /out/ \;
        '
}

check_packages() {
    local arch="$1"
    log "Installing ${arch} packages into a clean Debian Trixie container"
    docker run --rm \
        --platform "linux/${arch}" \
        -v "${OUT_DIR}:/artifacts:ro" \
        -e "ARCH=${arch}" \
        -e "PRODUCTS=${PRODUCTS[*]}" \
        debian:trixie-slim bash -c '
            set -euo pipefail
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq >/dev/null
            for product in ${PRODUCTS}; do
                package="$(ls -t /artifacts/${product}_*_"${ARCH}".deb | head -n 1)"
                apt-get install -y -qq --no-install-recommends "${package}" >/dev/null
            done
            for product in ${PRODUCTS}; do
                binary="$(command -v "${product}")"
                printf "%-32s %s\n" "${product}" "$("${binary}" --version)"
                "${binary}" --help >/dev/null
                if ldd "${binary}" | grep -q "not found"; then
                    echo "${product}: unresolved shared libraries" >&2
                    ldd "${binary}" >&2
                    exit 1
                fi
            done
        '
}

for arch in "${ARCHES[@]}"; do
    image="$(build_image "${arch}")"
    build_packages "${arch}" "${image}"
    if [[ "${RUN_CHECK}" -eq 1 ]]; then
        check_packages "${arch}"
    fi
done

log "Artifacts in ${OUT_DIR}"
for arch in "${ARCHES[@]}"; do
    ls -1t "${OUT_DIR}"/*_"${arch}".deb 2>/dev/null | head -n "${#PRODUCTS[@]}" | while read -r package; do
        printf '  %s\n' "$(basename "${package}")"
    done
done
