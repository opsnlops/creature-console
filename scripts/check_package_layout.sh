#!/usr/bin/env bash
#
# Check built packages against the fleet packaging policy, reading the archives themselves:
#
#   scripts/check_package_layout.sh <dir-with-debs> <arch>
#
# - Debian Policy 10.1: nothing under the aliased /bin, /sbin or /lib*. An installed, usr-merged
#   filesystem hides this mistake behind its symlinks, so read `dpkg-deb --contents`.
# - Every package ships its manual page, and every package with secrets keeps /etc/default/<pkg>
#   at 0600 - dh_fixperms once silently reset it to 0644.
# - Every binary is hardened: W^X segments, GNU_RELRO and BIND_NOW.
#
# Needs dpkg-deb and readelf (binutils): the CI runner has both; build_debs.sh installs binutils.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <dir-with-debs> <arch>" >&2
    exit 2
fi

dir="$1"
arch="$2"
status=0

for package in "${dir}"/*_"${arch}".deb; do
    if dpkg-deb --contents "${package}" | grep -E ' \./(bin|sbin|lib[^/]*)/'; then
        echo "error: ${package} ships files under an aliased path (Debian Policy 10.1)" >&2
        status=1
    fi
done

# Every package ships its manual page (section 1 for creature-cli, 8 for the daemons), and every
# package with secrets keeps /etc/default/<pkg> at 0600.
for entry in creature-cli:1 creature-mqtt:8 creature-world:8 creature-house:8 creature-body:8 \
    creature-communicator-gateway:8 creature-agent:8; do
    name="${entry%:*}"
    section="${entry#*:}"
    package="$(ls -t "${dir}/${name}"_[0-9]*_"${arch}".deb 2>/dev/null | head -n 1)"
    if [[ -z "${package}" ]]; then
        echo "error: no ${name} package for ${arch} in ${dir}" >&2
        status=1
        continue
    fi
    contents="$(dpkg-deb --contents "${package}")"
    if ! grep -Eq " \./usr/share/man/man${section}/${name}\.${section}\.gz$" <<<"${contents}"; then
        echo "error: ${package} has no usr/share/man/man${section}/${name}.${section}.gz" >&2
        status=1
    fi
    case "${name}" in
        creature-cli | creature-mqtt) continue ;; # no packaged secrets file
    esac
    if ! grep -Eq "^-rw------- root/root .* \./etc/default/${name}$" <<<"${contents}"; then
        echo "error: ${package}: etc/default/${name} is not 0600 root:root" >&2
        status=1
    fi
done

# Hardened linking (debian/rules SWIFT_HARDENING): no segment both writable and executable,
# a GNU_RELRO segment, and BIND_NOW. GNU ld's Swift output is one RWE segment, so a regression
# to it fails here rather than only in the report-only lintian.
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
for package in "${dir}"/creature-*_[0-9]*_"${arch}".deb; do
    [[ "${package}" == *-dbgsym_* ]] && continue
    unpacked="${work}/$(basename "${package}" .deb)"
    dpkg-deb -x "${package}" "${unpacked}"
    for binary in "${unpacked}"/usr/bin/*; do
        name="$(basename "${binary}")"
        segments="$(readelf -lW "${binary}")"
        if grep -E '^\s+LOAD' <<<"${segments}" | grep -q 'RWE'; then
            echo "error: ${name} has a writable and executable LOAD segment" >&2
            status=1
        fi
        if ! grep -q 'GNU_RELRO' <<<"${segments}"; then
            echo "error: ${name} has no GNU_RELRO segment" >&2
            status=1
        fi
        if ! readelf -dW "${binary}" | grep -q 'BIND_NOW'; then
            echo "error: ${name} is not linked with BIND_NOW" >&2
            status=1
        fi
    done
done

if [[ "${status}" -eq 0 ]]; then
    echo "package layout: ok (${arch})"
fi
exit "${status}"
