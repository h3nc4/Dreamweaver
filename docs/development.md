# Development

How to work on this repository. [AGENTS.md](../AGENTS.md) records why each decision was made and what breaks if it is undone. This file covers the process.

---

## Host requirements

Docker. The dev container holds the toolchain, and being asked to install `xorriso`, QEMU, OVMF, `shellcheck` or `shfmt` on your machine means something is wrong.

---

## Getting a dev container

The image is `h3nc4/dreamweaver-dev:<tag>`, where the tag is whatever `.github/VERSION` contains. That image is published by pushing a `dc-v*.*.*` tag, so until the first one exists, build it locally:

```sh
./scripts/build-dev-image.sh
```

Both `build-dev-image.sh` and `build-iso.sh` read the tag from `.github/VERSION`, so a locally built image under a different tag will not be found. `DEV_IMAGE_REPO` changes the name in all three build scripts, and `scripts/vm.sh` also takes `DEV_IMAGE_TAG`.

Opening the repository in a dev container is the usual route. Running the container by hand needs the mounts the entrypoint checks for:

```sh
docker run --rm -it \
  -e "HOST_UID_GID=$(id -u):$(id -g)" \
  -v "${PWD}:/workspaces/Dreamweaver" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --device /dev/kvm \
  h3nc4/dreamweaver-dev:1 bash
```

`scripts/entrypoint.sh` then reconciles the container with the host:

* the container user takes your UID and GID, so files it writes are yours;
* the `docker` group takes the socket's GID;
* `/dev/kvm` is widened, which is what keeps the boot tests to minutes;
* `git` is pointed at `scripts/hooks`.

A missing Docker socket is a warning rather than a failure, because only `build-iso.sh` needs it.

---

## The loop

```sh
./scripts/lint.sh        # shellcheck -x -o all -s sh, then shfmt -w
./scripts/lint.sh -c     # check formatting instead of rewriting it
./scripts/ci.sh          # what the validate job runs, which today is lint -c
```

`lint.sh` rewrites formatting by default and `-c` only reports, which is the difference between the pre-commit hook passing and CI passing. Run `-c` before pushing.

The hooks are installed by the entrypoint, not by a setup step:

* `pre-commit` runs `ci.sh`.
* `pre-push` runs `ci.sh`, then `verify-iso.sh` over any `dreamweaver-*.iso` sitting in the tree. A stale image in your checkout gets re-checked for free.

---

## Working on the installer

`./install` chooses which modules run and does nothing itself. Each concern is one numbered module in `install.d`, and `lib/common` is what lets a module run alone.

```sh
./install --list                 # the modules, in run order
./install --dry-run -d -o        # what those flags would run
./install --only 070-packages    # one module
./install --from 120-grub        # resume from here
./install --skip 110-fonts       # everything except this
DW_DEV=1 ./install.d/200-dev-extras   # a module directly, no driver
```

Any unambiguous prefix works, so `--only 070` resolves and `--only 0` is refused with the list it matched.

These rules govern a module. AGENTS.md gives the reasoning under **The Installer**.

1. It runs on its own, sourcing `lib/common` and discovering what it needs from the machine.
2. Running it twice equals running it once. There are no completion markers anywhere in this tree.
3. Nothing calls `doas` directly. Everything goes through `as_root`, which is what makes a module testable in a container.
4. A precondition that does not hold produces a `skip`, and a `skip` counts as success.

Numbers are fixed width in steps of ten, because `100-` sorts before `15-`.

---

## Building images

From the host:

```sh
./scripts/build-iso.sh              # one image per base distribution
./scripts/build-iso.sh -d devuan    # only this one
./scripts/build-iso.sh -t           # unattended test images
```

Inside the container, `cook-image.sh` is the single-image primitive `iso.Dockerfile` calls:

```sh
./scripts/cook-image.sh -d debian       # repack, verify, report
./scripts/cook-image.sh -d devuan -t    # unattended test image
```

The flag you pick decides what you get, and the wrong one wastes a long test run:

| Flag | Preseed | Use it for |
| --- | --- | --- |
| none | `preseed/default.cfg` | what gets published, and anything you install by hand |
| `-t` | `preseed/unattended.cfg` | `test-install.sh`, `test-profile.sh` and `test-interactive.sh` |
| `-n` | either | omitting the payload, so the install downloads the release tarball instead |

A `-t` image answers every question, including this project's own profile question, and sets `console=ttyS0,115200n8` so the installer renders to the serial console. **If questions are arriving over serial, or no questions arrive at all, you are on a `-t` image.** Build one without `-t` to install by hand.

`-K` skips the upstream signature check. It exists for working offline against a cached base image, not for CI.

---

## Testing

Reach for the cheapest layer that can see the bug.

| Script | Costs | Catches |
| --- | --- | --- |
| `verify-iso.sh <iso>` | a second | boot catalog missing its UEFI entry, no hybrid partition table, an unseeded initrd, a stale `md5sum.txt` |
| `test-modules.sh` | minutes | a module that crashes, or that changes something on a second run it should not |
| `test-profile.sh <iso>` | minutes | the profile dialog missing when it should appear, or appearing when preseeded |
| `test-interactive.sh <iso>` | under a minute | answers given at the dialogue not reaching the installer as flags |
| `test-interactive.sh -f <iso>` | tens of minutes | the whole chain, from a keystroke to a package on a disk |
| `test-install.sh <iso>` | tens of minutes | an image that installs and boots under one firmware but not the other |

`test-modules.sh` runs every module twice against a container of the target base, and the second run is the point. A container lacks `/boot/grub`, `/etc/crypttab` and an init system as PID 1, so modules skip, and a skip counts as a pass. The slow modules sit behind `-a`.

`test-install.sh` and `test-interactive.sh -f` want `/dev/kvm`. They work under TCG and take long enough that you will not want to wait.

Both firmwares get tested, always. A suite that only covered BIOS is how an image reached release that no UEFI machine could boot.

---

## Seeing it on a screen

Everything above is headless, because debconf renders to the serial console where `expect` and `grep` can read it. That says whether the answers reached the installer. It says nothing about what the dialogue looks like to somebody meeting it for the first time, or whether the desktop that lands is usable. `scripts/vm.sh` is for those questions, and it asserts nothing.

```sh
./scripts/vm.sh <image.iso>            # install it by hand
./scripts/vm.sh -f uefi <image.iso>    # the other firmware
./scripts/vm.sh -b                     # boot what got installed
./scripts/vm.sh -r <image.iso>         # discard the disk and start over
```

The screen is a web page: the script prints a URL like `http://<host>:6080/vnc.html?autoconnect=1&resize=scale`, and nothing needs installing to open it. `-V 5900` also publishes the raw RFB port for a real client, and `-l` binds to localhost for an SSH tunnel.

Use an image built without `-t`. The disk persists under `scratch/vm/`, so an install you sat through is still there tomorrow. The terminal you are left at is QEMU's monitor, where `quit` stops the VM and `screendump out.ppm` takes a picture.

Debian's boot menu starts speech synthesis after thirty seconds without a keypress. That countdown is upstream's accessibility feature, not a fault in the image.

---

## CI

| Workflow | Trigger | Does |
| --- | --- | --- |
| `development.yaml` | push, PR | lint and toolchain checks in the dev image, `install.d` twice per module on both bases, then both images built and their boot layout verified |
| `boot-test.yaml` | dispatch, paths | the profile question, an interactive install over serial, then a full unattended install, 2 distributions x 2 firmwares |
| `devcontainer.yaml` | `dc-v*.*.*` tag | publishes the dev image, then commits the new tag back |
| `release.yaml` | `v*.*.*` tag | payload and both images, verified then signed, then released |
| `security.yaml` | push, PR, daily | `actionlint` over the workflows, Trivy over the dev image |

CI runs inside the dev image, so a check that passes locally passes there. Changing `docker/dev.Dockerfile` means the published image no longer matches what the tree expects: `development.yaml` builds a candidate for that PR, but a later push that leaves the Dockerfile alone pulls the published image again. Push a `dc-v*.*.*` tag to publish the new one.

Actions are pinned by commit SHA, and Renovate auto-merges minor, patch, pin and digest updates.

---

## Definition of done

A change to the image pipeline is done when `./scripts/ci.sh` passes and:

* `test-modules.sh` passes on both bases, if anything under `install.d`, `lib` or `packages` changed;
* `cook-image.sh` builds for both `-d debian` and `-d devuan`;
* `test-profile.sh` and `test-interactive.sh` pass on both, if anything under `preseed/` changed;
* `verify-iso.sh` passes on both, including the UEFI check;
* `test-install.sh` installs and boots both, under both firmwares;
* the dev image still builds, if it was touched.

---

## Conventions

POSIX `sh` everywhere, checked with `shellcheck -o all -s sh` and formatted by `shfmt` defaults, which means tabs. There is no bash in this repository.

What gets installed onto a target machine has no file extension, because `./install` is what a person types. What a developer runs sits in `scripts/` and ends in `.sh`.

Never hard-wrap a paragraph in Markdown. One paragraph is one line, however long, and the same goes for a list item or a table row. Code fences are exempt.

Comments carry only what the code cannot:

* a format or layout difference between the two base distributions, and what breaks if it is ignored;
* why a non-obvious approach was chosen over the obvious one;
* a constraint found by measurement, so nobody re-litigates it.

Delete anything that restates the code.
