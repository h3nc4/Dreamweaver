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

# Installs an image unattended under QEMU, then boots the result, once per firmware. A
# BIOS-only pass is what let a broken UEFI boot catalog ship, so -f uefi is the interesting
# half.
#
# Needs an image built with `cook-image.sh -t`, whose preseed also asks for console=ttyS0,
# which is how the second phase tells a booted system from a black screen.

set -e

cd "$(dirname "$0")/../"

FIRMWARE='both'
DISK_SIZE='12G'
INSTALL_TIMEOUT='2700'
BOOT_TIMEOUT='300'
MEMORY='2048'
OUT_DIR="scratch/boot-test"

die() {
	echo "$0: $*" >&2
	exit 1
}

usage() {
	cat >&2 <<-EOF
		Usage: $0 [-f bios|uefi|both] [-m MiB] [-o dir] <image.iso>

		  -f  firmware to test (default: ${FIRMWARE})
		  -m  guest memory in MiB (default: ${MEMORY})
		  -o  where to keep disks, logs and screenshots (default: ${OUT_DIR})
	EOF
	exit 1
}

OPTIND=1
while getopts "f:m:o:" opt; do
	case "${opt}" in
	f) FIRMWARE="${OPTARG}" ;;
	m) MEMORY="${OPTARG}" ;;
	o) OUT_DIR="${OPTARG}" ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

ISO="$1"
[ -n "${ISO}" ] || usage
[ -s "${ISO}" ] || die "${ISO} is missing or empty"

command -v qemu-system-x86_64 >/dev/null 2>&1 ||
	die "qemu-system-x86_64 not found. Run this inside the dev container."

case "${FIRMWARE}" in
bios | uefi | both) ;;
*) die "unknown firmware '${FIRMWARE}'" ;;
esac

OVMF_CODE=
OVMF_VARS=
for dir in /usr/share/OVMF /usr/share/ovmf /usr/share/qemu; do
	for code in OVMF_CODE_4M.fd OVMF_CODE.fd OVMF.fd; do
		if [ -f "${dir}/${code}" ]; then
			OVMF_CODE="${dir}/${code}"
			break
		fi
	done
	[ -n "${OVMF_CODE}" ] && break
done
for dir in /usr/share/OVMF /usr/share/ovmf; do
	for vars in OVMF_VARS_4M.fd OVMF_VARS.fd; do
		if [ -f "${dir}/${vars}" ]; then
			OVMF_VARS="${dir}/${vars}"
			break
		fi
	done
	[ -n "${OVMF_VARS}" ] && break
done

# TCG is only slow, so a host without /dev/kvm still runs the suite.
ACCEL='tcg'
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
	ACCEL='kvm'
else
	echo "Warning: no usable /dev/kvm; falling back to TCG. Expect this to take a while." >&2
fi

mkdir -p "${OUT_DIR}"

################################################################################

# run_qemu <firmware> <timeout> <label> <extra args...>
run_qemu() {
	_fw="$1"
	_timeout="$2"
	_label="$3"
	shift 3

	set -- \
		-machine "q35,accel=${ACCEL}" \
		-cpu max \
		-m "${MEMORY}" \
		-smp 2 \
		-drive "file=${_disk},format=qcow2,if=virtio" \
		-netdev user,id=net0 \
		-device virtio-net-pci,netdev=net0 \
		-display none \
		-vga std \
		-serial "file:${OUT_DIR}/${_label}.serial.log" \
		-monitor "unix:${OUT_DIR}/${_label}.monitor,server,nowait" \
		-no-reboot \
		"$@"

	if [ "${_fw}" = "uefi" ]; then
		cp -f "${OVMF_VARS}" "${OUT_DIR}/${_label}.vars.fd"
		set -- \
			-drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
			-drive "if=pflash,format=raw,unit=1,file=${OUT_DIR}/${_label}.vars.fd" \
			"$@"
	fi

	: >"${OUT_DIR}/${_label}.serial.log"
	timeout "${_timeout}" qemu-system-x86_64 "$@" >"${OUT_DIR}/${_label}.qemu.log" 2>&1
}

screenshot() {
	# Best effort: a picture of where a stuck guest stopped is worth having, but a
	# missing socket must not mask the real error.
	[ -S "${OUT_DIR}/$1.monitor" ] || return 0
	printf 'screendump %s\n' "${OUT_DIR}/$1.ppm" |
		timeout 10 socat - "unix-connect:${OUT_DIR}/$1.monitor" >/dev/null 2>&1 || :
}

test_firmware() {
	_fw="$1"
	echo "################################################################"
	echo "# ${_fw}: installing"

	if [ "${_fw}" = "uefi" ]; then
		[ -n "${OVMF_CODE}" ] || die "no OVMF firmware found; install the ovmf package"
		[ -n "${OVMF_VARS}" ] || die "no OVMF variable store found; install the ovmf package"
	fi

	_disk="${OUT_DIR}/${_fw}.qcow2"
	rm -f "${_disk}"
	qemu-img create -q -f qcow2 "${_disk}" "${DISK_SIZE}"

	# -no-reboot turns the installer's final reboot into a clean exit, the signal that
	# the preseed ran to the end.
	if ! run_qemu "${_fw}" "${INSTALL_TIMEOUT}" "${_fw}-install" \
		-drive "file=${ISO},format=raw,if=none,id=cd,media=cdrom,readonly=on" \
		-device ide-cd,drive=cd,bootindex=0; then
		screenshot "${_fw}-install"
		die "${_fw}: the installer did not finish. See ${OUT_DIR}/${_fw}-install.*"
	fi

	echo "# ${_fw}: booting the installed system"
	if ! run_qemu "${_fw}" "${BOOT_TIMEOUT}" "${_fw}-boot"; then
		# A timeout is expected, since nothing shuts the guest down. The serial log
		# below is what decides.
		:
	fi

	if grep -qE 'login:|Dreamweaver|Welcome to' "${OUT_DIR}/${_fw}-boot.serial.log"; then
		echo "# ${_fw}: PASS"
	else
		screenshot "${_fw}-boot"
		echo "# ${_fw}: FAIL - the installed system did not reach a login prompt" >&2
		echo "# last serial output:" >&2
		tail -n 30 "${OUT_DIR}/${_fw}-boot.serial.log" >&2 || :
		return 1
	fi
}

rc=0
case "${FIRMWARE}" in
both)
	test_firmware bios || rc=1
	test_firmware uefi || rc=1
	;;
*)
	test_firmware "${FIRMWARE}" || rc=1
	;;
esac

exit "${rc}"
