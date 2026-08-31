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

# Static checks on a built image. Each is a way a repack has silently produced a broken ISO:
#
#   * a BIOS-only boot catalog, which no UEFI machine boots
#   * a missing hybrid partition table, so it will not boot from USB
#   * a seed the installer never sees, turning an unattended install interactive
#   * a stale md5sum.txt, which fails the installer's integrity check
#
# One second, no privileges, so CI can gate on it.

set -e

ISO="$1"
[ -n "${ISO}" ] || {
	echo "Usage: $0 <image.iso>" >&2
	exit 1
}
[ -s "${ISO}" ] || {
	echo "$0: ${ISO} is missing or empty" >&2
	exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail=0

# Takes the command, not its exit status: with `cmd; check $?`, set -e kills the script
# before check runs.
check() {
	_desc="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		echo "  ok    ${_desc}"
	else
		echo "  FAIL  ${_desc}" >&2
		fail=1
	fi
}

echo "Verifying ${ISO}"

################################################################################
# Boot layout

xorriso -indev "${ISO}" -report_el_torito plain >"${WORK}/eltorito" 2>/dev/null || :
xorriso -indev "${ISO}" -report_system_area plain >"${WORK}/sysarea" 2>/dev/null || :

check "BIOS boot image present" \
	grep -q 'El Torito boot img.*BIOS' "${WORK}/eltorito"

# Matters most, because genisoimage with hand-written isolinux options drops this entry,
# and the result then needs legacy CSM to boot at all.
check "UEFI boot image present" \
	grep -q 'El Torito boot img.*UEFI' "${WORK}/eltorito"

check "hybrid partition table present" \
	grep -qEi 'MBR|GPT' "${WORK}/sysarea"

################################################################################
# Seed

# Discovered, not assumed: Debian keeps initrds under install.amd/, Devuan under
# boot/isolinux/, and Debian's menu defaults to a second, graphical one. All must carry the
# seed, or the default entry drops to an interactive install.
xorriso -indev "${ISO}" -find / -name initrd.gz 2>/dev/null |
	sed -e "s/^'//" -e "s/'\$//" >"${WORK}/initrds"

md5_matches() {
	# Debian prefixes these paths with ./, Devuan does not.
	_want="$(awk -v a=".$1" -v b="${1#/}" '$2 == a || $2 == b {print $1}' \
		"${WORK}/md5sum.txt")"
	_got="$(md5sum "${WORK}/initrd.gz" | cut -d' ' -f1)"
	[ -n "${_want}" ] && [ "${_want}" = "${_got}" ]
}

if [ ! -s "${WORK}/initrds" ]; then
	check "installer initrd found" false
else
	have_md5=
	if xorriso -report_about SORRY -osirrox on -indev "${ISO}" \
		-extract /md5sum.txt "${WORK}/md5sum.txt" 2>/dev/null; then
		have_md5=y
	else
		echo "  skip  md5sum.txt absent from this image"
	fi

	while read -r initrd; do
		check "extracted ${initrd}" \
			xorriso -report_about SORRY -osirrox on -indev "${ISO}" \
			-extract "${initrd}" "${WORK}/initrd.gz"

		gzip -cd "${WORK}/initrd.gz" | cpio -t --quiet >"${WORK}/initrd.list" 2>/dev/null || :

		check "  preseed.cfg seeded" \
			grep -qE '^(\./)?preseed\.cfg$' "${WORK}/initrd.list"

		check "  late-command seeded" \
			grep -qE '^(\./)?late-command$' "${WORK}/initrd.list"

		check "  profile-select seeded" \
			grep -qE '^(\./)?profile-select$' "${WORK}/initrd.list"

		check "  dreamweaver.templates seeded" \
			grep -qE '^(\./)?dreamweaver\.templates$' "${WORK}/initrd.list"

		# A stale md5sum.txt shows up here rather than halfway through an install.
		if [ -n "${have_md5}" ]; then
			check "  md5sum.txt entry matches" md5_matches "${initrd}"
		fi

		rm -f "${WORK}/initrd.gz"
	done <"${WORK}/initrds"
fi

################################################################################
# Payload

if xorriso -indev "${ISO}" -lsl /dreamweaver.tar.gz >/dev/null 2>&1; then
	echo "  ok    payload embedded on the medium"
else
	echo "  info  no embedded payload; the installed system will download it"
fi

exit "${fail}"
