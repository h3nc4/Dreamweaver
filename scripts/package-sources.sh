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

# A markdown table of every installed package and the source it was built from, from the
# output of `dpkg-query -W -f="$(scripts/package-sources.sh -q)"`.

set -e

TITLE='Dreamweaver package sources'
FLAGS=
# shellcheck disable=SC2016
QUERY='${db:Status-Abbrev} ${Package} ${Version} ${source:Package} ${source:Version} ${Homepage}\n'

usage() {
	cat >&2 <<-EOF2
		Usage: $0 [-t title] [-p install flags] [dpkg-query output]
		       $0 -q

		  -t  heading of the document (default: ${TITLE})
		  -p  the flags ./install ran with, named in the introduction
		  -q  print the dpkg-query format this reads and exit

		Reads standard input when no file is given. Only installed packages are listed.
	EOF2
	exit 1
}

OPTIND=1
while getopts "t:p:q" opt; do
	case "${opt}" in
	t) TITLE="${OPTARG}" ;;
	p) FLAGS="${OPTARG}" ;;
	q)
		printf '%s\n' "${QUERY}"
		exit 0
		;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

[ "$#" -le 1 ] || usage

printf '# %s\n\n' "${TITLE}"
printf 'Every package on the installed system, with the upstream project it comes from and the source of the exact version installed.'
if [ -n "${FLAGS}" ]; then
	printf " The system was installed with \`./install%s\`." "${FLAGS}"
fi
printf " A version containing \`devuan\` was modified by Devuan and links to pkginfo.devuan.org, and every other version links to sources.debian.org.\n\n"
printf '| Package | Version | Source | This version |\n'
printf '|---------|---------|--------|--------------|\n'

# GitHub reads one ~ as strikethrough, and Debian versions use it often.
LC_ALL=C awk '
	function text(s) { gsub(/~/, "\\~", s); return s }
	function url(s) { gsub(/:/, "%3A", s); return s }
	$1 != "ii" || NF < 5 { next }
	{
		pkg = $2; ver = $3; src = $4; srcver = $5; home = $6
		if (home == "") {
			upstream = "-"
		} else {
			host = home
			sub(/^[a-zA-Z]+:\/\//, "", host)
			sub(/[\/?#:].*$/, "", host)
			sub(/^www\./, "", host)
			upstream = "[" host "](" home ")"
		}
		if (ver ~ /devuan/ || srcver ~ /devuan/)
			link = "https://pkginfo.devuan.org/cgi-bin/policy-query.html?c=package&q=" pkg
		else
			link = "https://sources.debian.org/src/" src "/" url(srcver) "/"
		printf "| %s | %s | %s | [%s](%s) |\n", pkg, text(ver), upstream, text(ver), link
	}
' "${1:--}" | LC_ALL=C sort -u
