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

# Installer images, built in a container, ISOs dropped in the repo root. The host needs
# only Docker.
#
# With no -d it builds one image per base distribution, which is what the project
# releases. The release workflow does the same as a matrix.

set -e

cd "$(dirname "$0")/../"

ALL_DISTROS='debian devuan'
DISTROS=''
COOK_FLAGS=''

DEV_IMAGE_REPO="${DEV_IMAGE_REPO:-$(./scripts/devcontainer-image.sh -r)}"

usage() {
	cat >&2 <<-EOF
		Usage: $0 [-d debian|devuan] [-t] [-n]

		  -d  build only this base distribution; repeatable.
		      Default is all of them: ${ALL_DISTROS}
		  -t  seed the unattended test preseed instead of the interactive one
		  -n  do not embed the payload; the installed system downloads it instead

		Set DEV_IMAGE_REPO to build against a dev image under another name.
	EOF
	exit 1
}

OPTIND=1
while getopts "d:tn" opt; do
	case "${opt}" in
	d)
		case " ${ALL_DISTROS} " in
		*" ${OPTARG} "*) DISTROS="${DISTROS} ${OPTARG}" ;;
		*)
			echo "$0: unknown distribution '${OPTARG}'" >&2
			usage
			;;
		esac
		;;
	t) COOK_FLAGS="${COOK_FLAGS} -t" ;;
	n) COOK_FLAGS="${COOK_FLAGS} -n" ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

DISTROS="${DISTROS:-${ALL_DISTROS}}"

dev_image_tag="$(./scripts/devcontainer-image.sh -t)"

# Checked here because BuildKit's own failure says only "not found", which hints at
# nothing.
#
# The manifest call keeps its output and is tried twice, because a registry that
# refuses for a moment and an image that was never published used to end in the
# same sentence. That happened on master at 6a3f802 on 2026-09-22, against an
# image published since 31 August, and the advice to build it was wrong. A pull
# request never sees this: it builds the image locally and asks no registry.
if ! docker image inspect "${DEV_IMAGE_REPO}:${dev_image_tag}" >/dev/null 2>&1; then
	manifest_ok=0
	manifest_err="$(docker manifest inspect "${DEV_IMAGE_REPO}:${dev_image_tag}" 2>&1 >/dev/null)" && manifest_ok=1

	if [ "${manifest_ok}" -eq 0 ]; then
		sleep 2
		manifest_err="$(docker manifest inspect "${DEV_IMAGE_REPO}:${dev_image_tag}" 2>&1 >/dev/null)" && manifest_ok=1
	fi

	if [ "${manifest_ok}" -eq 0 ]; then
		echo "$0: ${DEV_IMAGE_REPO}:${dev_image_tag} is not local, and the registry did not confirm it twice running." >&2
		echo "The registry said:" >&2
		echo "  ${manifest_err}" >&2
		echo "Read that before building. If the image is genuinely absent, build it once with:" >&2
		echo "  ./scripts/build-dev-image.sh" >&2
		exit 1
	fi
fi

for distro in ${DISTROS}; do
	echo "################################################################"
	echo "# Building ${distro}"
	docker build \
		-f docker/iso.Dockerfile \
		--build-arg DEV_IMAGE="${DEV_IMAGE_REPO}" \
		--build-arg DEV_IMAGE_TAG="${dev_image_tag}" \
		--build-arg DISTRO="${distro}" \
		--build-arg COOK_FLAGS="${COOK_FLAGS# }" \
		--output type=local,dest=. \
		.
done

echo "################################################################"
ls -1 dreamweaver-*.iso
