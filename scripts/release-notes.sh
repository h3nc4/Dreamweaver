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

# Release notes for the version in VERSION, written to standard output: the base versions,
# the artifacts given as arguments and the commit titles since the previous tag.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${ROOT}"
REF='HEAD'
PREVIOUS=

usage() {
	cat >&2 <<-EOF2
		Usage: $0 [-C repo] [-r ref] [-p previous tag] [artifact...]

		  -C  read commits from this repository (default: this one)
		  -r  last commit of the release (default: ${REF})
		  -p  tag of the previous release (default: the nearest v* tag before -r)
	EOF2
	exit 1
}

OPTIND=1
while getopts "C:r:p:" opt; do
	case "${opt}" in
	C) REPO="${OPTARG}" ;;
	r) REF="${OPTARG}" ;;
	p) PREVIOUS="${OPTARG}" ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

version="$(cat "${ROOT}/VERSION")"
debian="$("${ROOT}/scripts/cook-image.sh" -d debian -P)"
devuan="$("${ROOT}/scripts/cook-image.sh" -d devuan -P)"

if [ -z "${PREVIOUS}" ]; then
	PREVIOUS="$(git -C "${REPO}" describe --tags --abbrev=0 --match 'v*' "${REF}^" 2>/dev/null)" || PREVIOUS=
fi

describe() {
	case "$1" in
	dreamweaver-debian-amd64.iso | dreamweaver-devuan-amd64.iso)
		_distro="${1#dreamweaver-}"
		echo "the same image as \`dreamweaver-${version}-${_distro}\`, under a name every release keeps"
		;;
	*-debian-amd64.iso) echo "Debian ${debian} based installer image" ;;
	*-devuan-amd64.iso) echo "Devuan ${devuan} based installer image" ;;
	*-debian-packages.md) echo "every package a Debian install gets, with links to its source" ;;
	*-devuan-packages.md) echo "every package a Devuan install gets, with links to its source" ;;
	dreamweaver.tar.gz) echo "the installer, for a system already running Debian or Devuan" ;;
	SHA256SUMS) echo "SHA256 checksum of every file here" ;;
	*) echo "" ;;
	esac
}

echo "Dreamweaver ${version}, built on Debian ${debian} and Devuan ${devuan}."

if [ "$#" -gt 0 ]; then
	printf '\n## Artifacts\n\n'
	echo "Each file has a detached GPG signature beside it, named with \`.asc\` on the end."
	echo
	for artifact in "$@"; do
		name="$(basename "${artifact}")"
		case "${name}" in
		*.asc) continue ;;
		*) ;;
		esac
		what="$(describe "${name}")"
		if [ -n "${what}" ]; then
			echo "- \`${name}\`, ${what}"
		else
			echo "- \`${name}\`"
		fi
	done
fi

case " $* " in
*/SHA256SUMS" "* | *" SHA256SUMS "*)
	printf '\n## Verify\n\n'
	echo "Download \`SHA256SUMS\`, \`SHA256SUMS.asc\` and the files you want into one directory, and these commands check the signature and then the files."
	printf '\n```console\n'
	echo '$ wget -qO- https://h3nc4.com/dreamweaver.asc | gpg --import'
	echo '$ gpg --verify SHA256SUMS.asc SHA256SUMS'
	echo '$ sha256sum --ignore-missing -c SHA256SUMS'
	printf '```\n'
	;;
*) ;;
esac

if [ -n "${PREVIOUS}" ]; then
	range="${PREVIOUS}..${REF}"
	printf '\n## Changes since %s\n\n' "${PREVIOUS}"
else
	range="${REF}"
	printf '\n## Changes\n\n'
fi

# Bot commits are dependency bumps, which read better as a count than as a list.
git -C "${REPO}" log --reverse --format='%an%x09%s' "${range}" | awk -F '\t' '
	$1 ~ /\[bot\]$/ { bots++; next }
	{ print "- " $2; humans++ }
	END {
		if (bots == 1) line = "1 dependency update"
		else if (bots > 1) line = bots " dependency updates"
		if (humans == 0 && bots == 0) print "No changes."
		else if (line != "" && humans == 0) print line "."
		else if (line != "") print "\nPlus " line "."
	}
'
