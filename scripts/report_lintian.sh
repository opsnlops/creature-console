#!/usr/bin/env bash
#
# Run lintian over built packages in a clean debian:trixie container. Report-only: findings are
# printed, and the exit status is non-zero only when lintian itself could not run.
#
#   scripts/report_lintian.sh <dir-with-debs> [summary-file]
#
# The fleet packaging policy adopts lintian report-only first; whether any tag fails a build is a
# later decision, made per tag. Overrides, when decided, ship at
# /usr/share/lintian/overrides/<package>. If [summary-file] is given, it receives one line,
# "errors=<n> warnings=<n>", for CI to turn into an annotation.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <dir-with-debs> [summary-file]" >&2
    exit 2
fi

deb_dir="$(cd "$1" && pwd)"
summary="${2:-}"

shopt -s nullglob
debs=("${deb_dir}"/*.deb)
if [[ ${#debs[@]} -eq 0 ]]; then
    echo "No .deb files in ${deb_dir}" >&2
    exit 1
fi

report="$(docker run --rm -v "${deb_dir}:/debs:ro" debian:trixie bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq --no-install-recommends lintian >/dev/null
    lintian --version >&2
    # --fail-on none: tags never fail the run; a non-zero exit then means lintian itself broke.
    # Run as non-root, as the fleet policy recommends.
    runuser -u nobody -- lintian --fail-on none --info --display-info --tag-display-limit 0 /debs/*.deb
')"

printf '%s\n' "${report}"

errors="$(grep -c '^E: ' <<<"${report}" || true)"
warnings="$(grep -c '^W: ' <<<"${report}" || true)"
echo "lintian: ${errors} error(s), ${warnings} warning(s) across ${#debs[@]} package(s)"
if [[ -n "${summary}" ]]; then
    echo "errors=${errors} warnings=${warnings}" >"${summary}"
fi
