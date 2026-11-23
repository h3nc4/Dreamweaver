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

# The release scripts against fixed input, in seconds and with no network.

set -e

cd "$(dirname "$0")/../"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail=0

# expect_line <description> <file> <exact line>
expect_line() {
	if grep -qxF -- "$3" "$2"; then
		echo "  ok    $1"
	else
		echo "  FAIL  $1" >&2
		echo "        wanted: $3" >&2
		fail=1
	fi
}

expect_no_line() {
	if grep -qF -- "$3" "$2"; then
		echo "  FAIL  $1" >&2
		fail=1
	else
		echo "  ok    $1"
	fi
}

echo "package-sources.sh"

# Status, package, version, source, source version, homepage, as -q asks dpkg-query.
cat >"${WORK}/packages.txt" <<'EOF2'
ii  bash 5.2.37-2+b10 bash 5.2.37-2 http://tiswww.case.edu/php/chet/bash/bashtop.html
ii  apt 3.0.3devuan1 apt 3.0.3devuan1 https://git.devuan.org/devuan/apt
ii  bash-completion 1:2.16.0-7 bash-completion 1:2.16.0-7 https://github.com/scop/bash-completion
ii  abiword 3.0.6~dfsg-1 abiword 3.0.6~dfsg-1 https://www.abisource.com/
ii  base-passwd 3.6.7 base-passwd 3.6.7
rc  removed-pkg 1.0-1 removed-pkg 1.0-1 https://example.org/
EOF2

scripts/package-sources.sh -t 'Fixture' -p ' -x -d' "${WORK}/packages.txt" >"${WORK}/packages.md"
scripts/package-sources.sh -t 'Fixture' -p ' -x -d' <"${WORK}/packages.txt" >"${WORK}/stdin.md"

expect_line "heading" "${WORK}/packages.md" '# Fixture'
expect_line "Debian package links its source version, not the binNMU" "${WORK}/packages.md" \
	'| bash | 5.2.37-2+b10 | [tiswww.case.edu](http://tiswww.case.edu/php/chet/bash/bashtop.html) | [5.2.37-2+b10](https://sources.debian.org/src/bash/5.2.37-2/) |'
expect_line "Devuan version links pkginfo.devuan.org" "${WORK}/packages.md" \
	'| apt | 3.0.3devuan1 | [git.devuan.org](https://git.devuan.org/devuan/apt) | [3.0.3devuan1](https://pkginfo.devuan.org/cgi-bin/policy-query.html?c=package&q=apt) |'
expect_line "epoch colon is escaped in the link" "${WORK}/packages.md" \
	'| bash-completion | 1:2.16.0-7 | [github.com](https://github.com/scop/bash-completion) | [1:2.16.0-7](https://sources.debian.org/src/bash-completion/1%3A2.16.0-7/) |'
expect_line "tilde is escaped in text and kept in the link" "${WORK}/packages.md" \
	'| abiword | 3.0.6\~dfsg-1 | [abisource.com](https://www.abisource.com/) | [3.0.6\~dfsg-1](https://sources.debian.org/src/abiword/3.0.6~dfsg-1/) |'
expect_line "missing homepage" "${WORK}/packages.md" \
	'| base-passwd | 3.6.7 | - | [3.6.7](https://sources.debian.org/src/base-passwd/3.6.7/) |'
expect_no_line "a package not installed is left out" "${WORK}/packages.md" 'removed-pkg'
if [ "$(grep -c '^| [a-z]' "${WORK}/packages.md")" -eq 5 ] &&
	[ "$(sed -n '/^| abiword/=' "${WORK}/packages.md")" -lt "$(sed -n '/^| bash |/=' "${WORK}/packages.md")" ]; then
	echo "  ok    five rows under the header, sorted by name"
else
	echo "  FAIL  five rows under the header, sorted by name" >&2
	fail=1
fi
if cmp -s "${WORK}/packages.md" "${WORK}/stdin.md"; then
	echo "  ok    standard input reads the same as a file"
else
	echo "  FAIL  standard input reads the same as a file" >&2
	fail=1
fi

if grep -qF -- "-f='$(scripts/package-sources.sh -q)'" preseed/list-packages; then
	echo "  ok    preseed/list-packages asks dpkg-query for the format this reads"
else
	echo "  FAIL  preseed/list-packages asks dpkg-query for the format this reads" >&2
	fail=1
fi

echo "release-notes.sh"

# A git hook exports these, and they would point the scratch repository at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX

repo="${WORK}/repo"
git init -q "${repo}"
commit() {
	git -C "${repo}" -c user.name=h3nc4 -c user.email=dev@example.invalid \
		-c commit.gpgsign=false commit -q --allow-empty "$@"
}
commit -m 'before the previous release'
git -C "${repo}" -c tag.gpgsign=false tag v1.0.0
commit -m 'add a thing'
commit --author='renovate[bot] <bot@example.invalid>' -m 'Update some action digest to abc1234 (#2)'
commit -m 'fix the thing (#3)'

scripts/release-notes.sh -C "${repo}" \
	dreamweaver-3.1.0-debian-amd64.iso dreamweaver-3.1.0-debian-amd64.iso.asc \
	dreamweaver.tar.gz SHA256SUMS >"${WORK}/notes.md"

expect_line "names this version and both bases" "${WORK}/notes.md" \
	"Dreamweaver $(cat VERSION), built on Debian $(scripts/cook-image.sh -d debian -P) and Devuan $(scripts/cook-image.sh -d devuan -P)."
expect_line "describes an image" "${WORK}/notes.md" \
	"- \`dreamweaver-3.1.0-debian-amd64.iso\`, Debian $(scripts/cook-image.sh -d debian -P) based installer image"
expect_no_line "signatures are not listed one by one" "${WORK}/notes.md" 'iso.asc`'
expect_line "finds the previous tag" "${WORK}/notes.md" '## Changes since v1.0.0'
expect_line "lists a human commit" "${WORK}/notes.md" '- add a thing'
if [ "$(sed -n '/^- add a thing$/=' "${WORK}/notes.md")" -lt "$(sed -n '/^- fix the thing/=' "${WORK}/notes.md")" ]; then
	echo "  ok    oldest commit first"
else
	echo "  FAIL  oldest commit first" >&2
	fail=1
fi
expect_no_line "leaves a commit of the previous release out" "${WORK}/notes.md" 'before the previous release'
expect_no_line "leaves a bot commit out of the list" "${WORK}/notes.md" 'Update some action'
expect_line "counts the bot commit" "${WORK}/notes.md" 'Plus 1 dependency update.'
expect_line "says how to check SHA256SUMS" "${WORK}/notes.md" '$ sha256sum --ignore-missing -c SHA256SUMS'

exit "${fail}"
