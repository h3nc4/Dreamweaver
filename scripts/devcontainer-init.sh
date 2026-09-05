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

# Puts the image .devcontainer.json pins on this machine, so the editor always has something
# to start. Run from initializeCommand, the one lifecycle hook that runs on the host and
# before the container is created, which is the only place a missing image can still be fixed.
#
# A branch that bumped the pin names a version nothing has published, because publishing
# happens on main alone. Building it here is the same fallback CI takes, and it is why a
# branch that touches the dev image can still be opened.
#
# Runs on every start, so the path where nothing is needed has to stay cheap: one local
# inspect and no network.

set -eu

cd "$(dirname "$0")/../"

image="$(./scripts/devcontainer-image.sh)"
label="com.h3nc4.local-build"

if docker image inspect "${image}" >/dev/null 2>&1; then
  # A local build stands in until the release publishes the real one, so this is the moment
  # to take the published image instead. Nothing to do for an image that came from there.
  if docker image inspect "${image}" --format '{{json .Config.Labels}}' |
    grep -q "\"${label}\":\"true\""; then
    if docker pull -q "${image}" >/dev/null 2>&1; then
      echo "${image} is published now, so the local build of it is gone"
    fi
  fi
  exit 0
fi

# A version main has released is in the registry, and pulling it beats a second build of the
# same Dockerfile that would differ in every apt timestamp.
if docker pull -q "${image}" >/dev/null 2>&1; then
  echo "pulled ${image}"
  exit 0
fi

# Labelled, so the branch above can tell this apart from the published image later.
echo "${image} is not published yet, so building it from this checkout"
docker build --label "${label}=true" -f docker/dev.Dockerfile -t "${image}" .
