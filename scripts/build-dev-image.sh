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

# The dev image, built locally under the name and tag the workflows pull. Needed before
# the first tag is pushed, and whenever the published image is behind dev.Dockerfile.

set -e

cd "$(dirname "$0")/../"

DEV_IMAGE_REPO="${DEV_IMAGE_REPO:-${DOCKERHUB_USERNAME:-h3nc4}/dreamweaver-dev}"
dev_image_tag="$(cat .github/VERSION)"

docker build \
	-f docker/dev.Dockerfile \
	-t "${DEV_IMAGE_REPO}:${dev_image_tag}" \
	.

echo "Built ${DEV_IMAGE_REPO}:${dev_image_tag}"
