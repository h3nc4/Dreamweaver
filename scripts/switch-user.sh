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

# switch-user.sh <username> <uid> <gid> <script> [args...]
# Sets the user's UID/GID, then re-executes the caller as that user.

set -e

username="$1"
target_uid="$2"
target_gid="$3"
shift 3

current_gid=$(id -g "${username}")
if [ "${target_gid}" != "${current_gid}" ]; then
	echo "Updating ${username} GID to ${target_gid}..."
	groupmod -o -g "${target_gid}" "${username}"
fi

current_uid=$(id -u "${username}")
if [ "${target_uid}" != "${current_uid}" ]; then
	echo "Updating ${username} UID to ${target_uid}..."
	usermod -o -u "${target_uid}" "${username}"
fi

echo "Re-executing as ${username} (UID:GID = ${target_uid}:${target_gid})..."
exec gosu "${username}" /bin/sh "$@"
