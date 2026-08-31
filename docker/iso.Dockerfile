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

################################################################################
# An installer image built with the dev image's toolchain, so the host needs only Docker.
# The final stage is FROM scratch, making the ISO the whole output, which
# `--output type=local,dest=.` drops in the working directory.

ARG DEV_IMAGE="h3nc4/dreamweaver-dev"
ARG DEV_IMAGE_TAG="latest"

FROM ${DEV_IMAGE}:${DEV_IMAGE_TAG} AS builder

ARG DISTRO="debian"
ARG COOK_FLAGS=""

USER root
WORKDIR /workspaces/Dreamweaver

COPY --chown=1000:1000 . .

# The base netinst is hundreds of megabytes and changes only on a point release, so it
# belongs in a cache mount rather than a layer.
RUN --mount=type=cache,target=/var/cache/dreamweaver,sharing=locked \
  set -e \
  && ./scripts/cook-image.sh -d "${DISTRO}" ${COOK_FLAGS} \
  && mkdir -p /out \
  && mv dreamweaver-*.iso /out/

################################################################################
# The image alone
FROM scratch AS final

COPY --from=builder /out/ /
