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
# The only place the toolchain is installed, so the host needs no xorriso, QEMU or OVMF.

########################################
# Runtime user
ARG USER="dreamweaver"
ARG UID="1000"
ARG GID="1000"

########################################
# Upstream signing keys, pinned by fingerprint. cook-image.sh refuses a base image whose
# checksum file is not signed by one of these.
ARG DEBIAN_CD_FINGERPRINT="DF9B9C49EAA9298432589D76DA87E80D6294BE9B"
ARG DEVUAN_CD_FINGERPRINT="185E56E98DA03B6CEADAC81983161D4768BE620B"

################################################################################
# Debian main stage
FROM debian:trixie@sha256:f324c7ff54321e8d9c588493a20244965938ce0aa50bbd1022d38010e9ffc4b1 AS main
ARG USER
ARG UID
ARG GID

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq

# Gen locale
RUN apt-get install --no-install-recommends -y -qq locales && \
  echo "en_US.UTF-8 UTF-8" >/etc/locale.gen && \
  locale-gen en_US.UTF-8 && \
  update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

RUN apt-get install --no-install-recommends -y -qq \
  bash-completion \
  ca-certificates \
  curl \
  file \
  git \
  gnupg \
  gosu \
  iproute2 \
  iputils-ping \
  jq \
  less \
  man-db \
  nano \
  opendoas \
  openssh-client \
  procps \
  psmisc \
  tini \
  tree \
  wget

# ISO authoring. xorriso is what debian-cd itself uses, and the only tool that can report
# and replay an existing image's boot layout, which is what keeps UEFI across a repack.
RUN apt-get install --no-install-recommends -y -qq \
  cpio \
  gzip \
  xorriso

# Boot testing, both firmware paths: an ISO that boots only one of them is the bug.
RUN apt-get install --no-install-recommends -y -qq \
  ovmf \
  qemu-system-x86 \
  qemu-utils \
  seabios \
  socat

# A VM on a screen without a VNC client: QEMU serves the RFB stream, and websockify both
# speaks WebSocket and serves the viewer. Used only by scripts/vm.sh, the manual test.
RUN apt-get install --no-install-recommends -y -qq \
  novnc \
  websockify

# Drives the installer's text frontend on the serial console, where debconf renders.
RUN apt-get install --no-install-recommends -y -qq \
  expect

# Linters used by the git hooks and CI.
RUN apt-get install --no-install-recommends -y -qq \
  shellcheck \
  shfmt

# Docker outside of Docker, used by scripts/build-iso.sh
RUN apt-get install --no-install-recommends -y -qq \
  docker-buildx \
  docker-cli

########################################
# Fetched here, not at repack time, so a repack never contacts a keyserver, and checked
# against the fingerprints above so a hostile one cannot substitute a key.
ARG DEBIAN_CD_FINGERPRINT
ARG DEVUAN_CD_FINGERPRINT
ENV DREAMWEAVER_KEYS="/usr/local/share/dreamweaver/keys"
RUN set -e; \
  mkdir -p "${DREAMWEAVER_KEYS}"; \
  for spec in "debian:${DEBIAN_CD_FINGERPRINT}" "devuan:${DEVUAN_CD_FINGERPRINT}"; do \
  name="${spec%%:*}"; fpr="${spec#*:}"; \
  curl -fsSL --retry 3 \
  "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${fpr}" \
  -o "${DREAMWEAVER_KEYS}/${name}.asc"; \
  gpg --quiet --with-colons --import-options show-only \
  --import "${DREAMWEAVER_KEYS}/${name}.asc" \
  | grep -q "^fpr:::::::::${fpr}:" \
  || { echo "key ${fpr} absent from the fetched ${name} keyring" >&2; exit 1; }; \
  done; \
  chmod 0644 "${DREAMWEAVER_KEYS}"/*.asc

########################################
# The non-root user, and doas
RUN addgroup --gid "${GID}" "${USER}"
RUN adduser --uid "${UID}" --gid "${GID}" \
  --shell "/bin/bash" --disabled-password "${USER}"

RUN addgroup --gid 110 docker && usermod -aG docker "${USER}"

# The installed system uses doas, so the container matches, with a sudo shim for tooling
# that shells out to sudo.
RUN printf "permit nopass nolog keepenv %s as root\n" "${USER}" >/etc/doas.conf && \
  chmod 400 /etc/doas.conf && \
  printf "%s\nset -e\n%s\n" "#!/bin/sh" "doas \"\$@\"" >/usr/local/bin/sudo && \
  chmod a+rx /usr/local/bin/sudo

# KVM makes the boot tests seconds rather than minutes, but a host without /dev/kvm must
# still work, so the group may be unused.
RUN getent group kvm >/dev/null || addgroup --system kvm
RUN usermod -aG kvm "${USER}"

COPY scripts/switch-user.sh /usr/local/bin/switch-user.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/switch-user.sh /usr/local/bin/entrypoint.sh

########################################
# Base images are written here. build-iso.sh mounts a cache over it so a repack does not
# re-download hundreds of megabytes.
ENV DREAMWEAVER_CACHE="/var/cache/dreamweaver"
RUN mkdir -p "${DREAMWEAVER_CACHE}" && chmod 0777 "${DREAMWEAVER_CACHE}"

########################################
# Clean cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
RUN rm -rf /var/log/* /tmp/*

################################################################################
# Final squash image.
FROM scratch AS final
ARG USER
ENV USER="${USER}" \
  LANG="en_US.UTF-8" \
  LC_ALL="en_US.UTF-8" \
  DREAMWEAVER_KEYS="/usr/local/share/dreamweaver/keys" \
  DREAMWEAVER_CACHE="/var/cache/dreamweaver" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

COPY --from=main / /

USER "${USER}"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/sleep", "infinity"]
