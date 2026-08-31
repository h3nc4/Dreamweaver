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

# Requires at least these flags:
#  -e "HOST_UID_GID=$(id -u):$(id -g)"
#  -v "${HOME}/:/home/dreamweaver/"
#  -v "${PWD}:/workspaces/Dreamweaver"
#  -v /var/run/docker.sock:/var/run/docker.sock

set -e

WORKSPACE="/workspaces/Dreamweaver"

if [ -d "${WORKSPACE}" ]; then
	cd "${WORKSPACE}"
else
	echo "Error: ${WORKSPACE} directory does not exist." >&2
	echo "Ensure the following flag is set in your run command:" >&2
	echo "  \`-v \${PWD}:${WORKSPACE}\`" >&2
	exit 1
fi

# Expected as UID:GID.
if [ -n "${HOST_UID_GID}" ]; then
	host_uid=$(echo "${HOST_UID_GID}" | cut -d: -f1)
	host_gid=$(echo "${HOST_UID_GID}" | cut -d: -f2)
elif [ -z "${DEVCONTAINER}" ]; then
	echo "HOST_UID_GID environment variable not set." >&2
	echo "Ensure the following flag is set in your run command:" >&2
	echo "  \`-e HOST_UID_GID=\$(id -u):\$(id -g)\`" >&2
	exit 1
fi

# Match the host's IDs if they differ.
current_uid=$(id -u dreamweaver)
current_gid=$(id -g dreamweaver)
if [ -z "${DEVCONTAINER}" ]; then
	if [ "${host_gid}" != "${current_gid}" ] || [ "${host_uid}" != "${current_uid}" ]; then
		echo "Current UID:GID (${current_uid}:${current_gid}) differs from host (${host_uid}:${host_gid})"
		echo "Updating dreamweaver user to match host..."
		exec doas /usr/local/bin/switch-user.sh dreamweaver "${host_uid}" "${host_gid}" "$0" "$@"
	fi
fi

# Only scripts/build-iso.sh needs the socket, so a missing one warns rather than fails.
if [ -S /var/run/docker.sock ]; then
	host_gid=$(stat -c '%g' /var/run/docker.sock)
	current_gid=$(getent group docker | cut -d: -f3)
	if [ "${host_gid}" != "${current_gid}" ]; then
		echo "Updating docker group GID to ${host_gid}..."
		doas groupmod -o -g "${host_gid}" docker
	fi
else
	echo "Warning: /var/run/docker.sock not found; scripts/build-iso.sh will not work." >&2
fi

# Without it QEMU uses TCG, turning a two-minute install test into twenty.
if [ -c /dev/kvm ]; then
	doas chmod a+rw /dev/kvm || echo "Could not widen /dev/kvm; boot tests will use TCG." >&2
else
	echo "Warning: /dev/kvm absent; boot tests will run under TCG and be slow." >&2
fi

# Activate the repository's hooks.
git config core.hooksPath scripts/hooks || :

doas mandb >/dev/null 2>&1

echo "Container initialized successfully."
echo "Run \`docker exec -it <container_name> bash\` to start developing."
exec "$@"
