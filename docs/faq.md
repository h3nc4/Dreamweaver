# FAQ

## Contents

1. [About Dreamweaver](#about-dreamweaver)
2. [System requirements](#system-requirements)
3. [Download and install](#download-and-install)
4. [Everyday use](#everyday-use)
5. [Software and drivers](#software-and-drivers)
6. [Virtual machines](#virtual-machines)
7. [Help and source code](#help-and-source-code)

## About Dreamweaver

### What is Dreamweaver?

Dreamweaver is a minimal desktop built on Debian or Devuan. It runs the dwm window manager on Xorg, with st as the terminal and dmenu as the launcher, all built from the project's own forks. There is no desktop environment and no display manager.

It comes as an installer image, and as a script that converts a Debian or Devuan system that is already installed. Both install the same system.

### What is it built on?

The installer image is the upstream Debian or Devuan netinst image with a preseed and two extra questions added to its installer, and the Dreamweaver install script added to the medium. Everything else on the image is upstream's.

The installer sets up the stable release, and Dreamweaver then moves the system to the testing release of the same distribution. Packages come from the upstream mirror, from `main` and `non-free-firmware`. Dreamweaver has no package repository of its own.

### Debian or Devuan?

Both images install the same Dreamweaver. The difference is the init system:

- The Debian image uses systemd, as Debian does.
- The Devuan image has no systemd. Its installer offers sysvinit, the default, OpenRC and runit.

## System requirements

| | |
|---|---|
| **Processor** | 64-bit x86 (amd64). There is no 32-bit or ARM image. |
| **Firmware** | BIOS or UEFI. |
| **Secure Boot** | Can stay on to boot the Debian image, must be off for the Devuan image. See [Does it work with Secure Boot?](#does-it-work-with-secure-boot) |
| **Network** | Required during the install. |
| **USB stick** | 1 GB or larger. |

| | Minimum |
|---|---|
| **Memory (RAM)** | 1 GB |
| **Disk** | 10 GB |

These minimums come from unattended installs of the Debian image with the default xorg session and no optional sets, under QEMU with KVM and BIOS firmware, on a 10 GB virtual disk. The install completed and the system booted with 1 GB of RAM and with 2 GB. On the 1 GB machine the installed system used 3.6 GB of disk, with 825 packages and a 583 MB swap partition that the installer created. Six minutes after boot, logged in at a text console with no X session running, it used 273 MB of RAM.

The installer image is about 800 MB for Debian and about 630 MB for Devuan.

## Download and install

### Where do I download Dreamweaver?

From the [Releases page](https://github.com/h3nc4/Dreamweaver/releases). Each release has one image per base distribution, a signature file for each image ending in `.asc`, and `dreamweaver.tar.gz` with its own `.asc` for converting an installed system.

### How do I check the download?

Each release image is signed with the Dreamweaver key. Download the image's `.asc` file from the same release, import the key, then verify the image against it, replacing `dreamweaver.iso` with the name of the downloaded file:

```console
$ wget -qO- https://h3nc4.com/dreamweaver.asc | gpg --import
$ gpg --verify dreamweaver.iso.asc dreamweaver.iso
```

For a good image, gpg prints `Good signature from "Dreamweaver <me@h3nc4.com>"`, made by key `3BC15CA502A834A6927527DA6B8614EABCBC4AA4`. gpg also warns that the key is not certified with a trusted signature, which only means it has not been signed by a key in the local keyring.

### How do I make a bootable USB stick?

Write the image to the stick as it is, with a raw image writer. This erases everything on the stick. The image has both an MBR and a GPT partition table, and a raw copy boots on BIOS and UEFI machines alike.

- **Linux**: find the stick with `lsblk`, then replace `sdX` with it:

  ```console
  $ sudo dd if=dreamweaver.iso of=/dev/sdX bs=4M status=progress conv=fsync
  ```

- **macOS**: find the stick with `diskutil list`, then replace `diskN` with it:

  ```console
  $ diskutil unmountDisk /dev/diskN
  $ sudo dd if=dreamweaver.iso of=/dev/rdiskN bs=4m
  ```

- **Windows**: use [Rufus](https://rufus.ie/) in **DD Image** mode, or [balenaEtcher](https://etcher.balena.io/).

### Does it work with Secure Boot?

The Debian image boots with Secure Boot on. Dreamweaver changes only the installer's initrd and leaves Debian's signed shim, GRUB and kernel as they are. Under UEFI firmware with Secure Boot enforced and the Microsoft keys enrolled, the Debian image boots to the installer. Booting the installed system with Secure Boot on has not been tested.

The Devuan image does not boot with Secure Boot on. The firmware refuses its loader with `Access Denied`, as it refuses the upstream Devuan 6.1.1 netinst image. Turn Secure Boot off in the firmware setup to install from it.

### How do I install Dreamweaver?

Boot from the USB stick and follow the installer, either the text one or the graphical one. It is the standard debian-installer, so it asks for language, keyboard, disk, user account and root password as Debian or Devuan would.

The installer needs a network connection the whole way. The netinst image contains only the base system, and the Dreamweaver setup downloads its window manager, configuration and fonts from GitHub.

### Which questions are added to the installer?

Two questions, before the disk is partitioned. The first picks the session:

- **xorg**, the default: dwm, st, dmenu and the sxac auto clicker, on Xorg, with Firefox, KeePassXC and the nsxiv image viewer.
- **headless**: no graphical software.

The second picks any optional sets, and takes more than one:

- **extra**: adds Signal and Brave from their own repositories, LibreOffice Writer and Calc, SimpleScreenRecorder, Bluetooth, a VNC viewer and a command-line torrent client.
- **development**: adds VSCodium, Docker, Chromium, compilers and build tools, SQLite tools, ShellCheck and shfmt, and a second account named `dev` that shares the first user's configuration.
- **gaming**: adds Steam and the 32-bit Mesa and Vulkan drivers. See [Can I play games?](#can-i-play-games)
- **virtualization**: adds QEMU, KVM, libvirt and virt-manager. See [Can I run virtual machines on it?](#can-i-run-virtual-machines-on-it)

Leaving both at their defaults installs xorg with no optional sets.

Every choice installs the core set as well: command-line tools such as tmux, neovim, git, gcc, mpv, ffmpeg, the lf file manager, the aerc mail client and the newsboat feed reader, plus PipeWire for audio and ufw. The full list is in [packages/](../packages).

### Does it support disk encryption?

Yes. In the partitioning step, pick **Guided - use entire disk and set up encrypted LVM**, which is debian-installer's own LUKS setup. The passphrase is asked once at boot.

Several volumes that share a passphrase are unlocked by typing it once. Dreamweaver adds the `decrypt_keyctl` keyscript to every line of `/etc/crypttab`, which keeps the passphrase in the kernel keyring during boot.

### Can I install it on a system that is already running?

Yes, on Debian or Devuan, as the regular user rather than as root:

```console
$ wget -qO- https://github.com/h3nc4/Dreamweaver/releases/latest/download/dreamweaver.tar.gz | tar xzf -
$ Dreamweaver/install
```

The script needs root once, through `sudo` or `su`, to install `doas`, and uses `doas` from then on. The installer's questions are flags here: `-o`, `-d`, `-g` and `-v` for the optional sets and `-h` for headless. The [README](../README.md) lists them all.

## Everyday use

### What happens at first boot?

There is no boot menu and no graphical login screen. The disk passphrase comes first on an encrypted disk, then a text login on the first console. Logging in there as the user created in the installer runs `startx`, which starts dwm. Logging in on any other console gives a shell. On the Debian image, in a QEMU virtual machine, Xorg currently fails to start at that point with `Cannot open virtual console 7`, and the login prompt comes back.

Automatic login depends on how Dreamweaver was installed. Where the init system is systemd or reads `/etc/inittab`, as sysvinit and OpenRC do, the script on a running system logs that user in on all six consoles without asking for a password, and dwm then starts on the first one. The Devuan image with sysvinit or OpenRC gets the same `/etc/inittab` setup. The Debian image leaves the login prompt in place. To lock the screen, press `super + ctrl + q`. To stay at a shell on the first console instead of starting dwm, create the file `~/.config/.skip-x`.

### How do I open the menu and a terminal?

| Keys | Action |
|---|---|
| `super + right shift` | Open dmenu, the application launcher |
| `super + q` | Open a terminal |
| `super + a` | Close the focused window |
| `super + w` | Open Firefox |
| `super + ctrl + q` | Lock the screen |
| `super + shift + s` | Shut down |
| `super + shift + r` | Reboot |

For every key binding, open a terminal and run:

```console
$ man dwm
```

### How do I run a command as root?

With `doas`, which Dreamweaver configures for the first user without a password prompt:

```console
$ doas apt install htop
```

### How do I update Dreamweaver?

Update the packages with apt, as on any Debian or Devuan system:

```console
$ doas apt update
$ doas apt full-upgrade
```

The system tracks the testing release, so new package versions arrive continuously rather than at point releases.

Dreamweaver itself has no package. To move to a newer Dreamweaver, which may change the package set or the configuration, download the latest `dreamweaver.tar.gz` and run its installer again with the same flags as the first time:

```console
$ wget -qO- https://github.com/h3nc4/Dreamweaver/releases/latest/download/dreamweaver.tar.gz | tar xzf -
$ Dreamweaver/install
```

The flags chosen at install time are not saved, so pass them again, such as `Dreamweaver/install -d` for a system installed with development. A flag left out removes nothing that it installed before.

A second run downloads the configuration again and unpacks it over `~/.config`, replacing every file of the same name. It also rewrites `/etc/profile`, deletes `/etc/bash.bashrc`, `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.bash_logout` and `~/.profile`, and replaces the Firefox `user.js`. Back up local changes to those files first.

## Software and drivers

### Is it all free software?

By default, yes, apart from device firmware. The package sources enable `main` and `non-free-firmware`, which is what Debian itself enables for firmware such as Wi-Fi firmware and CPU microcode. `contrib` and `non-free` are added only by the gaming set.

The extra set adds two outside repositories, for Signal and Brave, and the development set adds one, for VSCodium.

### Can I play games?

Choose **gaming** during the install, or pass `-g` to the script. Gaming enables the `contrib` and `non-free` components and the 32-bit architecture, then installs Steam with the 32-bit Mesa and Vulkan drivers. Steam is proprietary, so it is never installed by default.

When development is also selected, gaming creates a separate `steam` account that shares the first user's configuration, and the X session allows that account to open windows.

### Does it support NVIDIA graphics?

Without the proprietary driver, the kernel's open-source nouveau driver runs the card. The proprietary driver is not installed by the installer or by any flag. On a machine with an NVIDIA card, download the installer and run its NVIDIA module by hand:

```console
$ wget -qO- https://github.com/h3nc4/Dreamweaver/releases/latest/download/dreamweaver.tar.gz | tar xzf -
$ DW_NVIDIA=1 Dreamweaver/install.d/250-nvidia
```

It adds NVIDIA's own repository for Debian 13, pinned to NVIDIA's signing key by fingerprint, installs `nvidia-open`, the kernel headers and the NVIDIA firmware, blacklists nouveau and rebuilds the initramfs. Reboot afterwards for the driver to load. On a machine without an NVIDIA card it does nothing.

### Can I run virtual machines on it?

Choose **virtualization** during the install, or pass `-v` to the script. This installs QEMU, libvirt, virt-manager and the OVMF UEFI firmware and adds the user to the `libvirt` and `kvm` groups. On a running systemd system, the script leaves the libvirt services and sockets disabled, so start `libvirtd` before virt-manager can connect.

Press `super + v` to open virt-manager.

## Virtual machines

### Can I try Dreamweaver in a virtual machine?

Yes. The project's own tests install each image under QEMU with KVM, on BIOS and on UEFI firmware. Give the machine at least the [minimum memory and disk](#system-requirements).

## Help and source code

### Where do I report a bug?

In the [issue tracker](https://github.com/h3nc4/Dreamweaver/issues). For a problem during an install from the image, attach `/root/dreamweaver-install.log` from the installed system, which holds the output of every Dreamweaver step.

### Where is the source code?

The installer, the image build and the package lists are in [h3nc4/Dreamweaver](https://github.com/h3nc4/Dreamweaver). The window manager, terminal and launcher are the forks [h3nc4/dwm](https://github.com/h3nc4/dwm), [h3nc4/st](https://github.com/h3nc4/st) and [h3nc4/dmenu](https://github.com/h3nc4/dmenu), the auto clicker is [h3nc4/sxac](https://github.com/h3nc4/sxac), and the configuration installed into `~/.config` is [h3nc4/dotfiles](https://github.com/h3nc4/dotfiles). Each of these is downloaded as a release signed with the Dreamweaver key. The Hack and Terminus Nerd Fonts and the arkenfox Firefox settings are downloaded over HTTPS without a signature check.

To build the images, see [development.md](development.md).
