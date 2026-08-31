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

# Repacks an upstream Debian or Devuan netinst image into a Dreamweaver installer.
#
# Edited in place: xorriso replays the upstream boot configuration and replaces only the
# changed files, keeping BIOS boot, UEFI boot, the hybrid partition table and the signed
# shim chain without knowing their layout.
#
# Needs no privileges. Only the installer initrds are touched, in a temporary directory.

set -e

cd "$(dirname "$0")/../"

DISTRO='debian'
VERSION=
UNATTENDED=
EMBED_PAYLOAD=y
VERIFY_SIG=y

die() {
	echo "$0: $*" >&2
	exit 1
}

usage() {
	cat >&2 <<-EOF
		Usage: $0 [-d debian|devuan] [-V version] [-t] [-n] [-K]

		  -d  base distribution to repack (default: ${DISTRO})
		  -V  override the base image version
		  -t  seed the unattended test preseed instead of the interactive one
		  -n  do not embed the payload; the installed system downloads it instead
		  -K  skip signature verification of the upstream checksum file
	EOF
	exit 1
}

OPTIND=1
while getopts "d:V:tnK" opt; do
	case "${opt}" in
	d) DISTRO="${OPTARG}" ;;
	V) VERSION="${OPTARG}" ;;
	t) UNATTENDED=y ;;
	n) EMBED_PAYLOAD= ;;
	K) VERIFY_SIG= ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

for tool in xorriso cpio gzip curl gpg; do
	command -v "${tool}" >/dev/null 2>&1 ||
		die "${tool} not found. Run this inside the dev container."
done

case "${DISTRO}" in
debian)
	VERSION="${VERSION:-13.6.0}"
	BASE_ISO="debian-${VERSION}-amd64-netinst.iso"
	BASE_URL="https://cdimage.debian.org/debian-cd/${VERSION}/amd64/iso-cd"
	SUMS='SHA256SUMS'
	SUMS_SIG='SHA256SUMS.sign'
	;;
devuan)
	VERSION="${VERSION:-6.1.1}"
	CODENAME='excalibur'
	BASE_ISO="devuan_${CODENAME}_${VERSION}_amd64_netinstall.iso"
	BASE_URL="https://files.devuan.org/devuan_${CODENAME}/installer-iso"
	SUMS='SHA256SUMS.txt'
	SUMS_SIG='SHA256SUMS.txt.asc'
	;;
*)
	die "unknown distribution '${DISTRO}'"
	;;
esac

OUT_ISO="dreamweaver-${DISTRO}-${VERSION}-amd64.iso"
CACHE="${DREAMWEAVER_CACHE:-${PWD}}"
KEYS="${DREAMWEAVER_KEYS:-/usr/local/share/dreamweaver/keys}"

mkdir -p "${CACHE}"
BASE="${CACHE}/${BASE_ISO}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fetch() {
	if [ -n "${CI}" ]; then
		curl -fsSL --retry 3 -o "$1" "$2"
	else
		curl -fL --progress-bar --retry 3 -o "$1" "$2"
	fi
}

# One file out of the base image.
extract() {
	xorriso -report_about SORRY -osirrox on -indev "${BASE}" -extract "$1" "$2" 2>/dev/null
}

################################################################################
# Base image

if [ ! -f "${BASE}" ]; then
	echo "Fetching ${BASE_ISO}..."
	fetch "${BASE}.part" "${BASE_URL}/${BASE_ISO}" || {
		rm -f "${BASE}.part"
		die "could not fetch ${BASE_ISO}. A newer point release may have replaced it; pass -V."
	}
	mv "${BASE}.part" "${BASE}"
fi

echo "Verifying ${BASE_ISO}..."
fetch "${WORK}/${SUMS}" "${BASE_URL}/${SUMS}"
fetch "${WORK}/${SUMS_SIG}" "${BASE_URL}/${SUMS_SIG}"

if [ -n "${VERIFY_SIG}" ]; then
	[ -f "${KEYS}/${DISTRO}.asc" ] ||
		die "no ${DISTRO} signing key at ${KEYS}. Run inside the dev container, or pass -K."
	GNUPGHOME="${WORK}/gnupg"
	export GNUPGHOME
	mkdir -p "${GNUPGHOME}"
	chmod 700 "${GNUPGHOME}"
	gpg --quiet --import "${KEYS}/${DISTRO}.asc"
	gpg --quiet --verify "${WORK}/${SUMS_SIG}" "${WORK}/${SUMS}" ||
		die "${SUMS} is not signed by the pinned ${DISTRO} key"
fi

EXPECTED="$(awk -v f="${BASE_ISO}" '$2 == f || $2 == "*" f {print $1}' "${WORK}/${SUMS}")"
[ -n "${EXPECTED}" ] || die "${BASE_ISO} is not listed in ${SUMS}"
(cd "${CACHE}" && echo "${EXPECTED}  ${BASE_ISO}" | sha256sum -c -) ||
	die "${BASE_ISO} does not match ${SUMS}; delete it and retry"

################################################################################
# Seed

SEED="${WORK}/seed"
mkdir -p "${SEED}" "${WORK}/in"

if [ -n "${UNATTENDED}" ]; then
	cat preseed/unattended.cfg "preseed/mirror-${DISTRO}.cfg" >"${SEED}/preseed.cfg"
else
	cp preseed/default.cfg "${SEED}/preseed.cfg"
fi
cp preseed/late-command "${SEED}/late-command"

# The profile question and its templates. profile-select runs from early_command, so it
# must be executable inside the initrd.
cp preseed/profile-select "${SEED}/profile-select"
cp preseed/dreamweaver.templates "${SEED}/dreamweaver.templates"
chmod +x "${SEED}/profile-select"

# debian-installer reads /preseed.cfg from the initrd root with no boot parameter, so the
# seed goes there and not onto the ISO filesystem.
#
# Every initrd is seeded, not just the first: Debian's boot menu defaults to the graphical
# installer, so seeding only the text one leaves the default path interactive. Locations
# differ too, Debian install.amd/ against Devuan boot/isolinux/.
xorriso -indev "${BASE}" -find / -name initrd.gz 2>/dev/null |
	sed -e "s/^'//" -e "s/'\$//" >"${WORK}/initrds"
[ -s "${WORK}/initrds" ] || die "no initrd.gz in ${BASE_ISO}"

# md5sum.txt is edited, not regenerated: both images carry symlinks back to the root, so
# walking the tree either loops or drops entries, and upstream's list is already right for
# everything left alone.
#
# Debian writes ./install.amd/initrd.gz, Devuan boot/isolinux/initrd.gz, so the prefix is
# read off the file rather than assumed.
MD5_PREFIX=''
HAVE_MD5=
if extract /md5sum.txt "${WORK}/md5sum.txt"; then
	HAVE_MD5=y
	chmod u+w "${WORK}/md5sum.txt"
	if head -n 1 "${WORK}/md5sum.txt" | grep -q '  \./'; then
		MD5_PREFIX='./'
	fi
fi

# update_md5 <local file> <path inside the image, with leading />
update_md5() {
	[ -n "${HAVE_MD5}" ] || return 0
	_key="${MD5_PREFIX}${2#/}"
	_sum="$(md5sum "$1" | cut -d' ' -f1)"
	grep -vF "  ${_key}" "${WORK}/md5sum.txt" >"${WORK}/md5sum.next" || :
	printf '%s  %s\n' "${_sum}" "${_key}" >>"${WORK}/md5sum.next"
	mv -f "${WORK}/md5sum.next" "${WORK}/md5sum.txt"
}

# Positional parameters, so the paths never go through word splitting.
set --

while read -r path; do
	echo "Seeding ${path}"
	local_gz="${WORK}/in/$(echo "${path#/}" | tr / _)"
	extract "${path}" "${local_gz}" || die "could not extract ${path}"
	chmod u+w "${local_gz}"

	gunzip "${local_gz}"
	(cd "${SEED}" && printf '%s\n' \
		preseed.cfg late-command profile-select dreamweaver.templates |
		cpio --quiet -H newc -o -A -F "${local_gz%.gz}")
	gzip -9n "${local_gz%.gz}"

	update_md5 "${local_gz}" "${path}"
	set -- "$@" -map "${local_gz}" "${path}"
done <"${WORK}/initrds"

# On the ISO filesystem, not in an initrd: an initrd is unpacked into RAM every boot, so
# megabytes of tarball there cost memory for a file read once, late, from the medium.
if [ -n "${EMBED_PAYLOAD}" ]; then
	scripts/make-tar.sh
	update_md5 dreamweaver.tar.gz /dreamweaver.tar.gz
	set -- "$@" -map "${PWD}/dreamweaver.tar.gz" /dreamweaver.tar.gz
fi

if [ -n "${HAVE_MD5}" ]; then
	set -- "$@" -map "${WORK}/md5sum.txt" /md5sum.txt
fi

################################################################################
# Repack
#
# One xorriso session loads the image, replays its boot configuration, replaces the changed
# files and writes the result. Rebuilding instead would also cost ~200 MB, since the
# upstream image shares extents between duplicate files and an extraction loses that.

rm -f "${OUT_ISO}"

xorriso \
	-indev "${BASE}" \
	-outdev "${PWD}/${OUT_ISO}" \
	-boot_image any replay \
	-overwrite on \
	"$@" \
	-commit

echo "Built ${OUT_ISO}"
scripts/verify-iso.sh "${OUT_ISO}"
