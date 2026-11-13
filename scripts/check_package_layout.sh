#!/usr/bin/env bash
#
# Check built packages against the fleet packaging policy, reading the archives themselves:
#
#   scripts/check_package_layout.sh <dir-with-debs> <arch>
#
# - Debian Policy 10.1: nothing under the aliased /bin, /sbin or /lib*. An installed, usr-merged
#   filesystem hides this mistake behind its symlinks, so read `dpkg-deb --contents`.
# - Every Creature World package ships its section-8 manual page and keeps /etc/default/<pkg>
#   (where its secrets live) at 0600 - dh_fixperms once silently reset it to 0644.
#
# Runs anywhere dpkg-deb exists: the CI runner, or the Debian image build_debs.sh uses.

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

for name in creature-world creature-house creature-body creature-communicator-gateway creature-agent; do
    package="$(ls -t "${dir}/${name}"_[0-9]*_"${arch}".deb 2>/dev/null | head -n 1)"
    if [[ -z "${package}" ]]; then
        echo "error: no ${name} package for ${arch} in ${dir}" >&2
        status=1
        continue
    fi
    contents="$(dpkg-deb --contents "${package}")"
    if ! grep -Eq " \./usr/share/man/man8/${name}\.8\.gz$" <<<"${contents}"; then
        echo "error: ${package} has no usr/share/man/man8/${name}.8.gz" >&2
        status=1
    fi
    if ! grep -Eq "^-rw------- root/root .* \./etc/default/${name}$" <<<"${contents}"; then
        echo "error: ${package}: etc/default/${name} is not 0600 root:root" >&2
        status=1
    fi
done

if [[ "${status}" -eq 0 ]]; then
    echo "package layout: ok (${arch})"
fi
exit "${status}"
