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

# Keeps the active HTTPS mirrors that serve a Debian-origin .deb themselves. Some answer
# those with a 302 to deb.debian.org, which apt follows silently.

set -e

cd "$(dirname "$0")/../"

SOURCE='https://pkgmaster.devuan.org/mirror_list.txt'
INDEX='https://pkgmaster.devuan.org/merged/dists/stable/main/binary-amd64/Packages.gz'
PROBE=''
OUT='mirrors/devuan.list'

usage() {
	cat >&2 <<-EOF
		Usage: $0 [-p <pool path>] [-o <file>]

		  -p  Debian-origin file each mirror must serve (default: hello in stable)
		  -o  where to write the list (default: ${OUT})
	EOF
	exit 1
}

OPTIND=1
while getopts 'p:o:' opt; do
	case "${opt}" in
	p) PROBE="${OPTARG}" ;;
	o) OUT="${OPTARG}" ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

for tool in curl gzip; do
	command -v "${tool}" >/dev/null 2>&1 || {
		echo "$0: ${tool} not found" >&2
		exit 1
	}
done

LIST="$(mktemp)"
FOUND="$(mktemp)"
trap 'rm -f "${LIST}" "${FOUND}"' EXIT

curl -fsS --max-time 60 -o "${LIST}" "${SOURCE}"

# Read from the index rather than pinned, since a pinned version 404s once Debian drops it.
if [ -z "${PROBE}" ]; then
	PROBE="$(curl -fsS --max-time 300 "${INDEX}" | gzip -dc |
		awk '/^Package: hello$/ { f = 1 } f && !d && /^Filename:/ { print $2; d = 1 }')"
	case "${PROBE}" in
	pool/DEBIAN/*) ;;
	*)
		echo "$0: no Debian-origin hello in ${INDEX}" >&2
		exit 1
		;;
	esac
fi
echo "probe:  ${PROBE}"

# One BaseURL per active HTTPS mirror. Records are blank-line separated, fields "Key:  value".
candidates="$(awk '
	function flush() {
		if (base != "" && active == "yes" && https) print base
		base = ""; active = ""; https = 0
	}
	/^[[:space:]]*$/ { flush(); next }
	{
		key = $1; sub(/:$/, "", key)
		val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]*$/, "", val)
		if (key == "BaseURL") { base = val; sub(/\/+$/, "", base) }
		else if (key == "Active") active = val
		else if (key == "Protocols" && toupper(val) ~ /(^|[^A-Z])HTTPS([^A-Z]|$)/) https = 1
	}
	END { flush() }
' "${LIST}")"

[ -n "${candidates}" ] || {
	echo "$0: no active HTTPS mirror in ${SOURCE}" >&2
	exit 1
}

# HEAD without following redirects, so a mirror that hands the file to another host fails.
status() {
	curl -sS -o /dev/null -I --max-time 20 -w '%{http_code}' "$1" 2>/dev/null || echo 000
}

for base in ${candidates}; do
	url="https://${base}/merged"
	release="$(status "${url}/dists/stable/InRelease")"
	deb="$(status "${url}/${PROBE}")"
	if [ "${release}" = 200 ] && [ "${deb}" = 200 ]; then
		echo "ok      ${url}"
		printf '%s\n' "${url}" >>"${FOUND}"
	else
		echo "reject  ${url} (InRelease ${release}, ${PROBE##*/} ${deb})"
	fi
done

[ -s "${FOUND}" ] || {
	echo "$0: no mirror passed, ${OUT} left as it was" >&2
	exit 1
}

mkdir -p "$(dirname "${OUT}")"
sort -u "${FOUND}" >"${OUT}"
echo "wrote $(wc -l <"${OUT}") mirrors to ${OUT}"
