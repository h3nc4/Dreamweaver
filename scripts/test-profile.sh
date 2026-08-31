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

# Tests the profile question in preseed/profile-select, on an image built with -t.
#
#   asks     answers not preseeded, so the dialog must appear
#   silent   answers preseeded, so the dialog must NOT appear, and the exported flags
#            must match what was preseeded
#
# boot-test.yaml depends on silent: a dialog there hangs an unattended install until the
# timeout, saying nothing.
#
# Booted through QEMU's -kernel and -initrd, which puts the text frontend on the serial
# console. From the image it would draw on the VGA framebuffer, with nothing to assert on.

set -e

cd "$(dirname "$0")/../"

OUT_DIR='scratch/profile-test'
TIMEOUT='300'
MEMORY='2048'

die() {
	echo "$0: $*" >&2
	exit 1
}

usage() {
	cat >&2 <<-EOF
		Usage: $0 [-o dir] [-m MiB] <image.iso>

		The image must have been built with \`cook-image.sh -t\`.

		  -o  where to keep kernels, disks and logs (default: ${OUT_DIR})
		  -m  guest memory in MiB (default: ${MEMORY})
	EOF
	exit 1
}

OPTIND=1
while getopts 'o:m:' opt; do
	case "${opt}" in
	o) OUT_DIR="${OPTARG}" ;;
	m) MEMORY="${OPTARG}" ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

ISO="$1"
[ -n "${ISO}" ] || usage
[ -s "${ISO}" ] || die "${ISO} is missing or empty"

for tool in qemu-system-x86_64 qemu-img xorriso cpio; do
	command -v "${tool}" >/dev/null 2>&1 ||
		die "${tool} not found. Run this inside the dev container."
done

ACCEL='tcg'
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
	ACCEL='kvm'
else
	echo "Warning: no usable /dev/kvm; falling back to TCG." >&2
fi

mkdir -p "${OUT_DIR}"

################################################################################
# The installer's kernel and initrd, discovered rather than assumed: Debian keeps them in
# install.amd as vmlinuz, Devuan in boot/isolinux as linux.

INITRD_PATH="$(xorriso -indev "${ISO}" -find / -name initrd.gz 2>/dev/null |
	sed -e "s/^'//" -e "s/'\$//" | grep -v '/gtk/\|/xen/' | head -n 1)"
[ -n "${INITRD_PATH}" ] || die 'no installer initrd in the image'

BOOT_DIR="$(dirname "${INITRD_PATH}")"
KERNEL_PATH=''
# -find rather than -lsl: xorriso exits 0 for an absent path, so -lsl "finds" anything.
for _k in vmlinuz linux; do
	if xorriso -indev "${ISO}" -find "${BOOT_DIR}" -name "${_k}" 2>/dev/null |
		grep -q .; then
		KERNEL_PATH="${BOOT_DIR}/${_k}"
		break
	fi
done
[ -n "${KERNEL_PATH}" ] || die "no kernel next to ${INITRD_PATH}"

echo "kernel: ${KERNEL_PATH}"
echo "initrd: ${INITRD_PATH}"

xorriso -report_about SORRY -osirrox on -indev "${ISO}" \
	-extract "${KERNEL_PATH}" "${OUT_DIR}/kernel" \
	-extract "${INITRD_PATH}" "${OUT_DIR}/initrd.gz" 2>/dev/null
chmod u+w "${OUT_DIR}/kernel" "${OUT_DIR}/initrd.gz"

# Each case appends its own preseed.cfg to a copy of the initrd. A later cpio member wins,
# so the override lands without unpacking anything.
DISTRO='debian'
case "${ISO}" in
*devuan*) DISTRO='devuan' ;;
*) ;;
esac

base_seed() {
	cat preseed/unattended.cfg "preseed/mirror-${DISTRO}.cfg" |
		grep -v '^dreamweaver dreamweaver/' |
		grep -v '^d-i preseed/early_command'
}

################################################################################

# boot <label> <seed file> <marker regex>
#
# Stops as soon as the marker appears: everything under test happens in the first minute,
# and a preseeded install left alone would spend twenty more saying nothing new.
boot() {
	_label="$1"
	_seed="$2"
	_marker="$3"

	rm -rf "${OUT_DIR}/seed-${_label}"
	mkdir -p "${OUT_DIR}/seed-${_label}"
	cp "${_seed}" "${OUT_DIR}/seed-${_label}/preseed.cfg"

	gunzip -c "${OUT_DIR}/initrd.gz" >"${OUT_DIR}/${_label}.initrd"
	(cd "${OUT_DIR}/seed-${_label}" && printf 'preseed.cfg\n' |
		cpio --quiet -H newc -o -A -F "../${_label}.initrd")
	gzip -9nf "${OUT_DIR}/${_label}.initrd"

	rm -f "${OUT_DIR}/${_label}.serial.log"
	qemu-img create -q -f qcow2 "${OUT_DIR}/${_label}.qcow2" 12G

	: >"${OUT_DIR}/${_label}.serial.log"
	timeout "${TIMEOUT}" qemu-system-x86_64 \
		-machine "q35,accel=${ACCEL}" -cpu max -m "${MEMORY}" -smp 2 \
		-kernel "${OUT_DIR}/kernel" -initrd "${OUT_DIR}/${_label}.initrd.gz" \
		-append 'console=ttyS0,115200n8 DEBIAN_FRONTEND=text TERM=linux' \
		-drive "file=${ISO},format=raw,if=none,id=cd,media=cdrom,readonly=on" \
		-device ide-cd,drive=cd \
		-drive "file=${OUT_DIR}/${_label}.qcow2,format=qcow2,if=virtio" \
		-netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
		-display none -serial "file:${OUT_DIR}/${_label}.serial.log" \
		-no-reboot >"${OUT_DIR}/${_label}.qemu.log" 2>&1 &
	_qpid="$!"

	_waited=0
	while kill -0 "${_qpid}" 2>/dev/null; do
		grep -qE "${_marker}" "${OUT_DIR}/${_label}.serial.log" 2>/dev/null && break
		[ "${_waited}" -ge "${TIMEOUT}" ] && break
		sleep 2
		_waited=$((_waited + 2))
	done

	kill "${_qpid}" 2>/dev/null || :
	wait "${_qpid}" 2>/dev/null || :

	tr -d '\r' <"${OUT_DIR}/${_label}.serial.log" >"${OUT_DIR}/${_label}.txt"
	printf '  (%ss)\n' "${_waited}"
}

fail=0
report() {
	if [ "$1" -eq 0 ]; then
		echo "  ok    $2"
	else
		echo "  FAIL  $2" >&2
		fail=1
	fi
}

################################################################################
# Case 1: not preseeded, so the dialog must appear.

echo
echo "case: asks when not preseeded"
base_seed >"${OUT_DIR}/asks.cfg"
printf 'd-i preseed/early_command string /profile-select\n' >>"${OUT_DIR}/asks.cfg"
boot asks "${OUT_DIR}/asks.cfg" 'Graphical session:'

grep -q 'Graphical session:' "${OUT_DIR}/asks.txt"
report $? 'the session question was displayed'

grep -q 'xorg \[\*\]' "${OUT_DIR}/asks.txt"
report $? 'xorg is offered as the default'

################################################################################
# Case 2: preseeded, so no dialog, and the exported flags must match.
#
# Deliberately not the defaults: xorg with no extras would pass even if profile-select
# ignored the answers entirely.

echo
echo "case: silent when preseeded, and exports the preseeded answers"
{
	base_seed
	cat <<-'SEED'
		dreamweaver dreamweaver/session select wayland
		dreamweaver dreamweaver/extras multiselect development, gaming, virtualization
		d-i preseed/early_command string /profile-select; /profile-select --export /tmp/p; echo "PROFILE-EXPORT: $(cat /tmp/p)" >/dev/console
	SEED
} >"${OUT_DIR}/silent.cfg"
boot silent "${OUT_DIR}/silent.cfg" 'PROFILE-EXPORT:|Graphical session:'

if grep -q 'Graphical session:' "${OUT_DIR}/silent.txt"; then
	report 1 'no dialog appeared'
else
	report 0 'no dialog appeared'
fi

grep -q "PROFILE-EXPORT: DW_INSTALL_FLAGS=' -w -d -g -v'" "${OUT_DIR}/silent.txt"
report $? 'the exported flags match the preseeded answers'

if [ "${fail}" -ne 0 ]; then
	echo
	echo "logs in ${OUT_DIR}" >&2
fi
exit "${fail}"
