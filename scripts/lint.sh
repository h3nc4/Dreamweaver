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

# Every executable here is POSIX sh, so shellcheck is pinned to that dialect.
#
# Suppressed:
#   SC1090/SC1091  sourced paths that exist only on the installed system
#                  (-x follows lib/common, which carries a source= directive)
#   SC2310/SC2311  `helper || die`, the error idiom throughout
#   SC2312         masked exit status inside command substitution
#   SC2317         helpers dispatched indirectly, as `check <desc> <cmd...>` does
#
# -c checks formatting instead of applying it, which is what CI wants: a job that
# rewrites the tree it checked out passes either way.

set -e

cd "$(dirname "$0")/../"

CHECK_ONLY=

OPTIND=1
while getopts "c" opt; do
	case "${opt}" in
	c) CHECK_ONLY=y ;;
	*)
		echo "Usage: $0 [-c]" >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

SHELL_SCRIPTS=$(find . -type f \
	-not -path "./.git/*" \
	-not -path "./scratch/*" \
	-print0 | xargs -0 grep -Il '^#!' | sort -u)

echo "Checking the following scripts:"
echo "${SHELL_SCRIPTS}"
echo ""

rc=0

echo "${SHELL_SCRIPTS}" | xargs shellcheck -x -P "${PWD}" -o all -s sh \
	-e SC1090 -e SC1091 -e SC2310 -e SC2311 -e SC2312 -e SC2317 || rc=1

if [ -n "${CHECK_ONLY}" ]; then
	echo "${SHELL_SCRIPTS}" | xargs shfmt -d || rc=1
else
	echo "${SHELL_SCRIPTS}" | xargs shfmt -w
fi

exit "${rc}"
