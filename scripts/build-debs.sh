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

# Every Dreamweaver package into dist/: one per deb/<package>/, and a metapackage per
# packages/<category>.list. The lists remain the only place the package set is written.

set -eu

cd "$(dirname "$0")/../"

VERSION="$(cat VERSION)"
MAINTAINER='Dreamweaver <me@h3nc4.com>'
KEY='deb/dreamweaver-archive-keyring/root/usr/share/keyrings/h3nc4-apt.asc'
KEY_FPR='13F99F470D1DED8047781E11FE06EC689335F63E'
STAGE='scratch/debs'
DIST='dist'

# Their repositories come from install.d/060-extra-repos and 250-nvidia, so they are
# Recommends, which apt skips while those repositories are absent.
THIRD_PARTY='codium signal-desktop brave-browser nvidia-open'

rm -rf "${STAGE}"
mkdir -p "${STAGE}/gnupg" "${DIST}"
chmod 0700 "${STAGE}/gnupg"
rm -f "${DIST}"/*.deb

GNUPGHOME="${STAGE}/gnupg" gpg --quiet --with-colons --show-keys "${KEY}" |
	grep -q "^fpr:::::::::${KEY_FPR}:" || {
	echo "$0: ${KEY} is not ${KEY_FPR}" >&2
	exit 1
}

# stage <package>: an empty tree with the copyright and changelog every package needs.
stage() {
	_doc="${STAGE}/$1/usr/share/doc/$1"
	mkdir -p "${STAGE}/$1/DEBIAN" "${_doc}"
	cp deb/copyright "${_doc}/copyright"
	printf '%s (%s) unstable; urgency=medium\n\n  * Dreamweaver %s.\n\n -- %s  %s\n' \
		"$1" "${VERSION}" "${VERSION}" "${MAINTAINER}" "$(date -R)" |
		gzip -9n >"${_doc}/changelog.gz"
}

# finish <package>, with the rest of its control file on stdin.
finish() {
	_root="${STAGE}/$1"
	find "${_root}" -type d -exec chmod 0755 {} +
	find "${_root}" -type f -exec chmod 0644 {} +
	for _script in preinst postinst prerm postrm; do
		[ -f "deb/$1/${_script}" ] || continue
		sed "s/@VERSION@/${VERSION}/g" "deb/$1/${_script}" >"${_root}/DEBIAN/${_script}"
		chmod 0755 "${_root}/DEBIAN/${_script}"
	done
	if [ -d "${_root}/etc" ]; then
		(cd "${_root}" && find etc -type f | sed 's,^,/,' | sort) >"${_root}/DEBIAN/conffiles"
	fi
	(cd "${_root}" && find . -path ./DEBIAN -prune -o -type f -exec md5sum {} + |
		sed 's,  \./,  ,' | sort -k2) >"${_root}/DEBIAN/md5sums"
	_size="$(du -sk --exclude=DEBIAN "${_root}" | cut -f1)"
	{
		printf 'Package: %s\nVersion: %s\nArchitecture: all\n' "$1" "${VERSION}"
		printf 'Maintainer: %s\nInstalled-Size: %s\n' "${MAINTAINER}" "${_size}"
		sed "s/@VERSION@/${VERSION}/g"
	} >"${_root}/DEBIAN/control"
	dpkg-deb --root-owner-group -Zxz --build "${_root}" "${DIST}/$1_${VERSION}_all.deb"
}

################################################################################
# Packages with files of their own

for dir in deb/*/; do
	pkg="$(basename "${dir}")"
	stage "${pkg}"
	[ -d "${dir}root" ] && cp -R "${dir}root/." "${STAGE}/${pkg}/"
	if [ -f "${dir}install" ]; then
		while read -r src dest; do
			mkdir -p "$(dirname "${STAGE}/${pkg}/${dest}")"
			cp "${src}" "${STAGE}/${pkg}/${dest}"
		done <"${dir}install"
	fi
	finish "${pkg}" <"${dir}control"
done

################################################################################
# Metapackages

# The parsing install.d/070-packages does, through dw_package_list in lib/common.
names() { sed -e 's/#.*//' -e 's/[[:space:]]*//g' -e '/^$/d' "$1"; }

# The first sentence of the comment under the licence header, as description lines.
summary() {
	awk '/LICENSE file/ { f = 1; next } f && /^# / { sub(/^# /, ""); print; exit }' "$1" |
		sed 's/\. .*/./'
}

# lintian rejects a dependency on an Essential package, which is always installed anyway.
essential() { [ "$(dpkg-query -W -f='${Essential}' "$1" 2>/dev/null)" = yes ]; }

# meta <package> <list> [extra Depends] [extra control lines]
meta() {
	_deps="$3"
	_recs=''
	for _name in $(names "$2"); do
		essential "${_name}" && continue
		case " ${THIRD_PARTY} " in
		*" ${_name} "*) _recs="${_recs:+${_recs}, }${_name}" ;;
		*) _deps="${_deps:+${_deps}, }${_name}" ;;
		esac
	done
	stage "$1"
	{
		printf 'Section: metapackages\nPriority: optional\n'
		printf 'Homepage: https://github.com/h3nc4/Dreamweaver\n'
		[ -z "${_deps}" ] || printf 'Depends: %s\n' "${_deps}"
		[ -z "${_recs}" ] || printf 'Recommends: %s\n' "${_recs}"
		[ -z "${4:-}" ] || printf '%s\n' "$4"
		printf 'Description: Dreamweaver %s packages\n' "${1#dreamweaver-}"
		{
			summary "$2"
			[ -z "${_recs}" ] || echo 'Packages from third-party repositories are only' \
				'recommended, so apt skips them until those repositories are configured.'
		} | fold -s -w 78 | sed -e 's/ *$//' -e 's/^/ /'
	} | finish "$1"
}

for list in packages/*.list; do
	category="$(basename "${list}" .list)"
	case "${category}" in *.*) continue ;; *) ;; esac

	extra=''
	[ "${category}" = core ] && extra='dreamweaver-base'

	# One archive serves both bases, so a per-distribution list is its own package, chosen
	# by an alternative whose first half exists only on the other base.
	for variant in packages/"${category}".*.list; do
		if [ ! -f "${variant}" ] || [ -z "$(names "${variant}")" ]; then
			continue
		fi
		distro="${variant#packages/"${category}".}"
		distro="${distro%.list}"
		case "${distro}" in
		devuan) other='systemd' own='devuan-keyring' fence='' ;;
		debian) other='devuan-keyring' own='' fence='Conflicts: devuan-keyring' ;;
		*)
			echo "$0: no rule for a ${distro} variant: ${variant}" >&2
			exit 1
			;;
		esac
		sub="dreamweaver-${category}-${distro}"
		meta "${sub}" "${variant}" "${own}" "${fence}"
		extra="${extra:+${extra}, }${other} | ${sub}"
	done

	meta "dreamweaver-${category}" "${list}" "${extra}"
done

ls -1 "${DIST}"/*.deb
