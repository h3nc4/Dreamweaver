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

# Widen /dev/kvm so the boot tests get hardware virtualization. Optional: QEMU falls back
# to TCG, so a missing device must not fail container start.

set -e

if [ -e /dev/kvm ]; then
	sudo chmod a+rw /dev/kvm ||
		echo "Could not widen /dev/kvm; boot tests will fall back to TCG." >&2
else
	echo "No /dev/kvm on this host; boot tests will fall back to TCG." >&2
fi
