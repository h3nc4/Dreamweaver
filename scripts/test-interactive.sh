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

# Installs an image the way a person does, by answering the questions.
#
# debconf renders to the serial console, so expect drives the profile dialogue. Everything
# d-i asks on its own account stays preseeded: Debian tests those, and matching
# twenty-five prompts would break on every point release.
#
#   default   answer, confirm the answers reached the installer. Under a minute.
#   -f        finish the install, boot it, check from inside what landed. Tens of minutes.
#
# -f is the end-to-end one: a keystroke becomes a package on a disk, nothing stubbed.

set -e

cd "$(dirname "$0")/../"

SESSION='headless'
EXTRAS=''
FULL=''
CHECK_ONLY=''
OUT_DIR='scratch/interactive-test'
MEMORY='2048'
ASK_TIMEOUT='300'
INSTALL_TIMEOUT='10800'

die() {
	echo "$0: $*" >&2
	exit 1
}

usage() {
	cat >&2 <<-EOF
		Usage: $0 [-s xorg|wayland|headless] [-e "extras"] [-f] [-o dir] [-m MiB] <image.iso>

		  -s  session to answer with (default: ${SESSION})
		  -e  space separated extras to answer with, from:
		      extra development gaming virtualization
		  -f  full install: finish it, boot it, and check what landed
		  -c  skip the install and re-check the disk already in the output directory
		  -o  where to keep kernels, disks and logs (default: ${OUT_DIR})
		  -m  guest memory in MiB (default: ${MEMORY})

		The image must have been built with \`cook-image.sh -t\`.

		headless with no extras is the default because it is the cheapest answer that
		still proves the dialogue changed the outcome. Pass -s and -e for a real one.
	EOF
	exit 1
}

OPTIND=1
while getopts 's:e:fco:m:' opt; do
	case "${opt}" in
	s) SESSION="${OPTARG}" ;;
	e) EXTRAS="${OPTARG}" ;;
	f) FULL=y ;;
	c)
		FULL=y
		CHECK_ONLY=y
		;;
	o) OUT_DIR="${OPTARG}" ;;
	m) MEMORY="${OPTARG}" ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))

ISO="$1"
[ -n "${ISO}" ] || usage
[ -s "${ISO}" ] || die "${ISO} is missing or empty"

for tool in expect qemu-system-x86_64 qemu-img xorriso cpio; do
	command -v "${tool}" >/dev/null 2>&1 ||
		die "${tool} not found. Run this inside the dev container."
done

################################################################################
# The requested answers, as the numbers the text frontend expects and the flags and
# packages they should produce.

case "${SESSION}" in
xorg) SESSION_NUM=1 ;;
wayland) SESSION_NUM=2 ;;
headless) SESSION_NUM=3 ;;
*) die "unknown session '${SESSION}'" ;;
esac

EXTRAS_NUM=''
EXPECT_FLAGS=''
WANT_PKGS=''
NOT_WANT_PKGS=''

for _e in ${EXTRAS}; do
	case "${_e}" in
	extra)
		EXTRAS_NUM="${EXTRAS_NUM}${EXTRAS_NUM:+ }1"
		EXPECT_FLAGS="${EXPECT_FLAGS} -o"
		WANT_PKGS="${WANT_PKGS} transmission-cli"
		;;
	development)
		EXTRAS_NUM="${EXTRAS_NUM}${EXTRAS_NUM:+ }2"
		EXPECT_FLAGS="${EXPECT_FLAGS} -d"
		WANT_PKGS="${WANT_PKGS} sqlitebrowser"
		;;
	gaming)
		EXTRAS_NUM="${EXTRAS_NUM}${EXTRAS_NUM:+ }3"
		EXPECT_FLAGS="${EXPECT_FLAGS} -g"
		WANT_PKGS="${WANT_PKGS} steam-installer"
		;;
	virtualization)
		EXTRAS_NUM="${EXTRAS_NUM}${EXTRAS_NUM:+ }4"
		EXPECT_FLAGS="${EXPECT_FLAGS} -v"
		WANT_PKGS="${WANT_PKGS} virt-manager"
		;;
	*) die "unknown extra '${_e}'" ;;
	esac
done

# The session flag comes first, matching the order profile-select emits.
case "${SESSION}" in
xorg)
	EXPECT_FLAGS=" -x${EXPECT_FLAGS}"
	WANT_PKGS="${WANT_PKGS} xorg"
	NOT_WANT_PKGS="${NOT_WANT_PKGS} foot"
	;;
wayland)
	EXPECT_FLAGS=" -w${EXPECT_FLAGS}"
	WANT_PKGS="${WANT_PKGS} foot"
	NOT_WANT_PKGS="${NOT_WANT_PKGS} xorg"
	;;
headless)
	EXPECT_FLAGS=" -h${EXPECT_FLAGS}"
	NOT_WANT_PKGS="${NOT_WANT_PKGS} xorg foot firefox"
	;;
*) ;;
esac

DISTRO='debian'
case "${ISO}" in
*devuan*) DISTRO='devuan' ;;
*) ;;
esac

echo "image:    ${ISO} (${DISTRO})"
echo "answers:  session=${SESSION} extras=${EXTRAS:-none}"
echo "expects:  DW_INSTALL_FLAGS='${EXPECT_FLAGS}'"
[ -n "${FULL}" ] && echo "mode:     full install"

ACCEL='tcg'
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
	ACCEL='kvm'
else
	echo "Warning: no usable /dev/kvm; falling back to TCG." >&2
fi

mkdir -p "${OUT_DIR}"

################################################################################
# Installer kernel and initrd: Debian keeps them in install.amd as vmlinuz, Devuan in
# boot/isolinux as linux.

INITRD_PATH="$(xorriso -indev "${ISO}" -find / -name initrd.gz 2>/dev/null |
	sed -e "s/^'//" -e "s/'\$//" | grep -v '/gtk/\|/xen/' | head -n 1)"
[ -n "${INITRD_PATH}" ] || die 'no installer initrd in the image'
BOOT_DIR="$(dirname "${INITRD_PATH}")"

KERNEL_PATH=''
for _k in vmlinuz linux; do
	if xorriso -indev "${ISO}" -find "${BOOT_DIR}" -name "${_k}" 2>/dev/null | grep -q .; then
		KERNEL_PATH="${BOOT_DIR}/${_k}"
		break
	fi
done
[ -n "${KERNEL_PATH}" ] || die "no kernel next to ${INITRD_PATH}"

xorriso -report_about SORRY -osirrox on -indev "${ISO}" \
	-extract "${KERNEL_PATH}" "${OUT_DIR}/kernel" \
	-extract "${INITRD_PATH}" "${OUT_DIR}/initrd.gz" 2>/dev/null
chmod u+w "${OUT_DIR}/kernel" "${OUT_DIR}/initrd.gz"

################################################################################
# Everything d-i asks is answered here. The profile question is not.
#
# The confirmation is echoed straight to /dev/console, because once the questions are done
# d-i hands the console to screen, and anything through screen's window arrives broken up
# by redraws.
#
# The installed system also gets a serial getty, which is how the full mode logs in.
# Devuan's sysvinit needs that spelled out. systemd starts one on a serial console.

SEED="${OUT_DIR}/seed.cfg"
{
	cat preseed/unattended.cfg "preseed/mirror-${DISTRO}.cfg" |
		grep -v '^dreamweaver dreamweaver/' |
		grep -v '^d-i preseed/early_command'

	cat <<-'SEED_EOF'

		d-i preseed/early_command string \
			/profile-select; \
			/profile-select --export /tmp/dw.profile; \
			echo "PROFILE-CONFIRM: $(cat /tmp/dw.profile)" >/dev/console
	SEED_EOF

	if [ -n "${FULL}" ]; then
		cat <<-'SEED_EOF'

			d-i preseed/late_command string \
				mv /late-command /target/root/; \
				cp /tmp/dw.profile /target/root/dreamweaver.profile; \
				if [ -f /cdrom/dreamweaver.tar.gz ]; then \
					cp /cdrom/dreamweaver.tar.gz /target/root/; \
				fi; \
				in-target sh -c 'if [ -f /etc/inittab ] && ! grep -q ttyS0 /etc/inittab; then echo "T0:23:respawn:/sbin/getty -L ttyS0 115200 vt100" >>/etc/inittab; fi'; \
				in-target /bin/sh /root/late-command
		SEED_EOF
	fi
} >"${SEED}"

rm -rf "${OUT_DIR}/seed"
mkdir -p "${OUT_DIR}/seed"
cp "${SEED}" "${OUT_DIR}/seed/preseed.cfg"

gunzip -c "${OUT_DIR}/initrd.gz" >"${OUT_DIR}/driven.initrd"
(cd "${OUT_DIR}/seed" && printf 'preseed.cfg\n' |
	cpio --quiet -H newc -o -A -F "../driven.initrd")
gzip -9nf "${OUT_DIR}/driven.initrd"

# Never in check-only mode: this blanks the disk, and -c exists to read one already
# installed. Guarding the expect phase but not this line cost an hour of install once.
if [ -z "${CHECK_ONLY}" ]; then
	rm -f "${OUT_DIR}/disk.qcow2"
	qemu-img create -q -f qcow2 "${OUT_DIR}/disk.qcow2" 12G
fi

################################################################################
# Drive it.

cat >"${OUT_DIR}/drive.exp" <<EXP
set timeout ${ASK_TIMEOUT}
log_file -noappend "${OUT_DIR}/install.log"

spawn qemu-system-x86_64 \\
	-machine q35,accel=${ACCEL} -cpu max -m ${MEMORY} -smp 2 \\
	-kernel "${OUT_DIR}/kernel" -initrd "${OUT_DIR}/driven.initrd.gz" \\
	-append "console=ttyS0,115200n8 DEBIAN_FRONTEND=text TERM=linux" \\
	-drive "file=${ISO},format=raw,if=none,id=cd,media=cdrom,readonly=on" \\
	-device ide-cd,drive=cd \\
	-drive "file=${OUT_DIR}/disk.qcow2,format=qcow2,if=virtio" \\
	-netdev user,id=n0 -device virtio-net-pci,netdev=n0 \\
	-display none -serial stdio -no-reboot

proc fatal {msg} {
	puts "\\nFAIL: \$msg"
	exit 1
}

# The session question. A timeout here means the dialogue never appeared, the regression
# this script exists to catch.
expect {
	"Graphical session:" {}
	timeout { fatal "the session question never appeared" }
	eof { fatal "the installer exited before asking anything" }
}
expect {
	-re {Prompt:[^\\n]*> } {}
	timeout { fatal "no prompt after the session question" }
}
send "${SESSION_NUM}\\r"

expect {
	"Optional software:" {}
	timeout { fatal "the extras question never appeared" }
	eof { fatal "the installer exited after the first question" }
}
expect {
	-re {Prompt:[^\\n]*> } {}
	timeout { fatal "no prompt after the extras question" }
}
send "${EXTRAS_NUM}\\r"

# What the answers became, emitted by the seed straight to the console.
#
# The fallback pattern must require the newline: expect matches whatever has arrived, so a
# pattern ending in [^\\n]* matches the line's first character and reports a mismatch.
expect {
	"PROFILE-CONFIRM: DW_INSTALL_FLAGS='${EXPECT_FLAGS}'" {
		puts "\\nOK: the answers became DW_INSTALL_FLAGS='${EXPECT_FLAGS}'"
	}
	-re {PROFILE-CONFIRM: [^\\n]*\\n} {
		fatal "wrong flags: \$expect_out(0,string)"
	}
	timeout { fatal "no confirmation from profile-select" }
	eof { fatal "the installer exited before confirming" }
}
EXP

if [ -n "${FULL}" ]; then
	cat >>"${OUT_DIR}/drive.exp" <<EXP

# Let the install run. -no-reboot turns its final reboot into a clean exit, the signal
# that the preseed ran to the end.
#
# An unanswered debconf question is failed on, not waited out: a preseed with a gap does
# not crash, it draws the question and idles until the timeout with the disk untouched.
# Reporting the question beats reporting an hour of silence, and it is how the missing
# apt-setup answers in preseed/unattended.cfg were found.
set timeout ${INSTALL_TIMEOUT}
puts "\\n... installing, this takes a while"
expect {
	eof {}
	-re {Prompt:[^\\n]*> } {
		fatal "the installer is asking something the preseed does not answer.\\n      Look for the question above this prompt in ${OUT_DIR}/install.log"
	}
	"Press enter to continue" {
		fatal "the installer stopped on a note, usually a failed step.\\n      Look above it in ${OUT_DIR}/install.log"
	}
	timeout { fatal "the install did not finish within ${INSTALL_TIMEOUT}s" }
}
EXP
fi

################################################################################

if [ -n "${CHECK_ONLY}" ]; then
	[ -s "${OUT_DIR}/disk.qcow2" ] ||
		die "no installed disk in ${OUT_DIR}; run without -c first"
	# A fresh qcow2 is a few hundred kilobytes and has nothing installed on it, so
	# booting it would report a missing login prompt rather than an empty disk.
	_size="$(wc -c <"${OUT_DIR}/disk.qcow2")"
	[ "${_size}" -gt 104857600 ] ||
		die "${OUT_DIR}/disk.qcow2 is only ${_size} bytes; there is no install on it"
	echo
	echo "skipping the install; re-checking ${OUT_DIR}/disk.qcow2"
else

	echo
	if expect -f "${OUT_DIR}/drive.exp"; then
		:
	else
		echo
		echo "logs in ${OUT_DIR}" >&2
		exit 1
	fi

	[ -n "${FULL}" ] || exit 0
fi

################################################################################
# Boot what was installed and read the package list out of it.

echo
echo "booting the installed system"

cat >"${OUT_DIR}/check.exp" <<EXP
set timeout 600
log_file -noappend "${OUT_DIR}/boot.log"

spawn qemu-system-x86_64 \\
	-machine q35,accel=${ACCEL} -cpu max -m ${MEMORY} -smp 2 \\
	-drive "file=${OUT_DIR}/disk.qcow2,format=qcow2,if=virtio" \\
	-netdev user,id=n0 -device virtio-net-pci,netdev=n0 \\
	-display none -serial stdio -no-reboot

set pkgs "${WANT_PKGS} ${NOT_WANT_PKGS}"
EXP

# A quoted heredoc from here: the guest command must reach expect with its own $p intact,
# and expect must send it without Tcl touching it, which is what the braces below do.
cat >>"${OUT_DIR}/check.exp" <<'EXP'
proc fatal {msg} {
	puts "\nFAIL: $msg"
	exit 1
}

expect {
	"login: " {}
	timeout { fatal "the installed system did not reach a login prompt" }
	eof { fatal "the installed system exited before login" }
}
send "h3nc4\r"
expect {
	-re {[Pp]assword: } {}
	timeout { fatal "no password prompt" }
}
send "h3nc4\r"

# Echo off first, or expect matches the command it just sent: a line carrying both
# DW-HAVE-xorg and DW-MISSING-xorg reported HAVE for a package that was not installed.
set timeout 30
expect { timeout {} -re {\$ |# } {} }
send "stty -echo\r"
set timeout 120

send "echo DW-SHELL-READY\r"
expect {
	"DW-SHELL-READY" {}
	timeout { fatal "could not get a shell on the installed system" }
}

# Braces, because ${Package} in a double-quoted send is a Tcl variable reference and would
# abort with "can't read Package: no such variable".
send {dpkg-query -W -f='${Package} ${Status}\n' 2>/dev/null | grep 'ok installed' | cut -d' ' -f1 >/tmp/pkgs; echo DW-PKGS-DONE}
send "\r"
expect {
	"DW-PKGS-DONE" {}
	timeout { fatal "could not list the installed packages" }
}

# One round trip per package. The shell parses the verdicts afterwards, because Tcl
# quoting is the least reliable part of this file.
send "for p in $pkgs; do "
send {if grep -qx "$p" /tmp/pkgs; then echo "DWPKG $p yes"; else echo "DWPKG $p no"; fi; done; echo DWPKG-END}
send "\r"
expect {
	"DWPKG-END" {}
	timeout { fatal "the package check did not finish" }
}

send "poweroff\r"
expect { eof {} timeout {} }
EXP

if ! expect -f "${OUT_DIR}/check.exp"; then
	echo
	echo "logs in ${OUT_DIR}" >&2
	exit 1
fi

################################################################################
# The verdicts, read out of the log.

verdict() {
	# verdict <package> -> yes | no | unknown
	#
	# grep -a with the NULs stripped: a serial log picks up stray NULs, and grep then
	# prints "binary file matches", which reported "no verdict" for three packages whose
	# verdicts were in the log.
	tr -d '\015\000' <"${OUT_DIR}/boot.log" |
		grep -aoE "DWPKG ${1} (yes|no)" | tail -n 1 | awk '{print $3}'
}

fail=0
for _p in ${WANT_PKGS}; do
	case "$(verdict "${_p}")" in
	yes) echo "  ok    ${_p} is installed" ;;
	no)
		echo "  FAIL  ${_p} should have been installed" >&2
		fail=1
		;;
	*)
		echo "  FAIL  no verdict for ${_p}" >&2
		fail=1
		;;
	esac
done

for _p in ${NOT_WANT_PKGS}; do
	case "$(verdict "${_p}")" in
	no) echo "  ok    ${_p} is absent, as chosen" ;;
	yes)
		echo "  FAIL  ${_p} was installed but the answers did not ask for it" >&2
		fail=1
		;;
	*)
		echo "  FAIL  no verdict for ${_p}" >&2
		fail=1
		;;
	esac
done

if [ "${fail}" -ne 0 ]; then
	echo
	echo "logs in ${OUT_DIR}" >&2
	exit 1
fi

echo
echo "the installed system matches the answers given at the dialogue"
