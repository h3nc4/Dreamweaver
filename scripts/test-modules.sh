#!/bin/sh
#
# Copyright (C) 2026  Henrique Almeida <me@h3nc4.com>
#
# This file is part of Dreamweaver.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Runs install.d modules in a throwaway container, each one twice.
#
# The second run is the point: a module that is not idempotent fails or duplicates on it.
#
# A container has no /boot/grub, no /etc/crypttab and no init as PID 1, so modules skip
# cleanly and a skip is a pass. This catches a crash, or a second run that changes state.
#
# Modules run as root by default, where as_root is a no-op. That never exercises doas,
# where a bug lived: keepenv handed root a PATH with no sbin, breaking every as_root
# usermod, useradd, update-grub and update-initramfs. -u is the mode that sees that class.

set -e

cd "$(dirname "$0")/../"

DISTRO='debian'
BASE=''
ALL=''
KEEP=''
DOAS=''

# Modules that install packages or compile from source: minutes each, so opt-in.
SLOW='020-system-upgrade 070-packages 100-suckless 110-fonts'

usage() {
	cat >&2 <<-EOF
		Usage: $0 [-d debian|devuan] [-b image] [-a] [-k] [module ...]

		  -d  base distribution to test against (default: ${DISTRO})
		  -b  override the container base image
		  -a  include the slow modules: ${SLOW}
		  -u  run as a regular user through doas, the way an install really does
		  -k  keep the container after a failure, for inspection

		With no module arguments every module is tested. A module may be a unique
		prefix, so 070 works.
	EOF
	exit 1
}

OPTIND=1
while getopts 'd:b:auk' opt; do
	case "${opt}" in
	d) DISTRO="${OPTARG}" ;;
	b) BASE="${OPTARG}" ;;
	a) ALL=y ;;
	u) DOAS=y ;;
	k) KEEP=y ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

case "${DISTRO}" in
debian) BASE="${BASE:-debian:trixie}" ;;
devuan) BASE="${BASE:-dyne/devuan:excalibur}" ;;
*)
	echo "$0: unknown distribution '${DISTRO}'" >&2
	exit 1
	;;
esac

command -v docker >/dev/null 2>&1 || {
	echo "$0: docker not found" >&2
	exit 1
}

################################################################################
# Which modules

resolve() {
	set -- install.d/"$1"*
	[ -f "$1" ] || {
		echo "$0: no such module: $1" >&2
		exit 1
	}
	[ "$#" -eq 1 ] || {
		echo "$0: ambiguous module: $*" >&2
		exit 1
	}
	basename "$1"
}

MODULES=''
if [ "$#" -gt 0 ]; then
	for a in "$@"; do
		MODULES="${MODULES} $(resolve "${a}")"
	done
else
	for m in install.d/*; do
		n="$(basename "${m}")"
		if [ -z "${ALL}" ]; then
			case " ${SLOW} " in
			*" ${n} "*) continue ;;
			*) ;;
			esac
		fi
		MODULES="${MODULES} ${n}"
	done
fi

################################################################################
# Run

CONTAINER="dreamweaver-test-$$"
cleanup() {
	[ -n "${KEEP}" ] && return 0
	docker rm -f "${CONTAINER}" >/dev/null 2>&1 || :
}
trap cleanup EXIT

echo "base:    ${BASE}"
if [ -n "${DOAS}" ]; then
	echo "as:      a regular user through doas"
else
	echo "as:      root, where as_root is a no-op"
fi
echo "modules:${MODULES}"
echo

# One long-lived container, so state accumulates as it does on a real install and module
# 050 sees what 040 did. A fresh container each would test far less.
if [ -n "${DOAS}" ]; then
	set -- -e DW_USER=dreamweaver -e DW_HOME=/home/dreamweaver
else
	set -- -e DW_ALLOW_ROOT=1 -e DW_USER=root -e DW_HOME=/root
fi

docker run -d --name "${CONTAINER}" \
	-v "${PWD}:/dreamweaver:ro" \
	-e DEBIAN_FRONTEND=noninteractive \
	"$@" \
	-e DW_OPT=1 -e DW_DEV=1 -e DW_GAMES=1 -e DW_VIRT=1 -e DW_XORG=1 -e DW_GUI=1 \
	"${BASE}" sleep infinity >/dev/null

# The tree is mounted read-only and copied in, since the modules write into it and would
# otherwise fail for the wrong reason.
#
# tar rather than cp -a for the one thing cp cannot do: skip scratch/, which holds test
# disks. cp -a copied tens of gigabytes into the container's writable layer.
docker exec "${CONTAINER}" sh -c '
	mkdir -p /work &&
		tar -C /dreamweaver --exclude=./scratch -cf - . | tar -C /work -xf - &&
		chmod 755 /work &&
		apt-get update -qq' >/dev/null

# The user and doas exactly as ./bootstrap sets them up. The modules below run in a login
# shell, since that is what strips sbin from PATH, the difference this mode covers.
if [ -n "${DOAS}" ]; then
	docker exec "${CONTAINER}" sh -c '
		useradd -m -u 1000 -s /bin/bash dreamweaver >/dev/null 2>&1 || :
		OGUSER=dreamweaver /work/bootstrap' >/dev/null
fi

# 020-system-upgrade is in the slow set, so what it installs is provided here. Otherwise
# the fetch-and-verify modules fail for a reason the harness created.
if [ -z "${ALL}" ]; then
	docker exec "${CONTAINER}" apt-get install -y -qq --no-install-recommends \
		ca-certificates gnupg wget bindfs >/dev/null
fi

run_module() {
	if [ -n "${DOAS}" ]; then
		docker exec "${CONTAINER}" su - dreamweaver -c "/work/install.d/$1"
	else
		docker exec -w /work "${CONTAINER}" "./install.d/$1"
	fi
}

pass=0
fail=0
failed=''

for m in ${MODULES}; do
	printf '%-24s ' "${m}"

	if ! run_module "${m}" >"/tmp/dw-${m}.1.log" 2>&1; then
		printf 'FAIL (first run)\n'
		sed 's/^/    /' "/tmp/dw-${m}.1.log" | tail -8
		fail=$((fail + 1))
		failed="${failed} ${m}"
		continue
	fi

	if ! run_module "${m}" >"/tmp/dw-${m}.2.log" 2>&1; then
		printf 'FAIL (not idempotent: second run failed)\n'
		sed 's/^/    /' "/tmp/dw-${m}.2.log" | tail -8
		fail=$((fail + 1))
		failed="${failed} ${m}"
		continue
	fi

	if grep -q '^    skipped:' "/tmp/dw-${m}.1.log"; then
		printf 'ok (skipped)\n'
	else
		printf 'ok\n'
	fi
	pass=$((pass + 1))
done

echo
echo "passed: ${pass}  failed: ${fail}"
if [ "${fail}" -gt 0 ]; then
	echo "failed modules:${failed}" >&2
	[ -n "${KEEP}" ] && echo "container kept: ${CONTAINER}" >&2
	exit 1
fi
