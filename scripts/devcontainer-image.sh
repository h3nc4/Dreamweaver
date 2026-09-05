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

# Prints the dev container's pinned image, or one half of it.
#
# The image key of .devcontainer.json is the only place the dev image is named, so every
# workflow reads it from here rather than keeping a copy of the name or the version.
#
# Usage: devcontainer-image.sh [-r|-t] [file]
#   -r     print the repository, without the tag
#   -t     print the tag alone
#   file   read this instead of .devcontainer.json, or - for standard input, which is how
#          a workflow reads the pin off another commit: git show main:.devcontainer.json
set -eu

part="ref"
case "${1:-}" in
  -r)
    part="repo"
    shift
    ;;
  -t)
    part="tag"
    shift
    ;;
  *) ;; # a file, or nothing at all
esac

file="${1:--}"
if [ "${file}" = "-" ] && [ $# -eq 0 ]; then
  file=".devcontainer.json"
fi
if [ "${file}" != "-" ] && [ ! -f "${file}" ]; then
  echo "${file} is not there" >&2
  exit 1
fi

# The first "image" key, which in a dev container definition is the top-level one. A key
# behind a // comment does not open its line, so a commented-out image is passed over.
ref="$(
  sed -n 's/^[[:space:]]*"image"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${file}" |
    head -n 1
)"
if [ -z "${ref}" ]; then
  echo "no image key in ${file}" >&2
  exit 1
fi

# A reference with no tag pulls whatever latest happens to be, which is the opposite of a
# pin. The colon has to sit in the last path element, since an earlier one is a registry's
# port.
case "${ref##*/}" in
  *:?*) ;;
  *)
    echo "the image in ${file} is '${ref}', which carries no tag" >&2
    exit 1
    ;;
esac

case "${part}" in
  repo) printf '%s\n' "${ref%:*}" ;;
  tag) printf '%s\n' "${ref##*:}" ;;
  *) printf '%s\n' "${ref}" ;;
esac
