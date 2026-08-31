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

# The payload the installer unpacks on the target: only what the installed system needs,
# so dev tooling and build artifacts stay out.

set -e

cd "$(dirname "$0")/../"

TMPFILE="$(mktemp --tmpdir tmp.XXXXXXXXXX.tar.gz)"
trap 'rm -f "${TMPFILE}"' EXIT

tar --transform 's,^\./,Dreamweaver/,' -czf "${TMPFILE}" \
	--exclude='./.git*' \
	--exclude='./scratch' \
	--exclude='*.iso' \
	--exclude='*.iso.asc' \
	--exclude='*.qcow2' \
	--exclude='*.vars.fd' \
	--exclude='*.ppm' \
	--exclude=dreamweaver.tar.gz \
	.

mv -f "${TMPFILE}" ./dreamweaver.tar.gz
