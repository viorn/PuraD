# PuraD

[**English**](README.md) | [Русский](README.ru.md)

A live distribution built on pure Debian: a live CD with KDE Plasma, out-of-the-box
installation to ext4/btrfs, and no third-party repositories.

## Quick start

```bash
# Build the ISO for trixie
make iso TARGET=trixie

# Build the ISO for sid
make iso TARGET=sid

# Test the ISO boot in qemu (BIOS + UEFI)
make test TARGET=trixie

# Verify that the image contains all Wi-Fi/GPU firmware
make firmware TARGET=trixie

# Install the system: VM with graphics + an empty 20G disk (builds/<target>/run/)
make run-install TARGET=trixie

# After installation — boot from the disk (without the CD, otherwise BIOS loads live again)
make run-installed TARGET=trixie

# The VM screen opens by itself: SPICE (faster), otherwise GTK, otherwise VNC.
# Choose manually: QEMU_VIEWER=gtk|spice|vnc|none
make run-installed TARGET=trixie QEMU_VIEWER=vnc

# Clean artifacts (the package cache is preserved)
make clean

# Remove everything, including the build cache
make distclean

# Show help
make help
```

## Build architecture

```
deked/
├── Makefile                  # make iso TARGET=trixie|sid
├── VERSION
├── container/
│   └── Dockerfile            # debian:{trixie,sid} + live-build
├── scripts/
│   ├── build.sh              # podman --privileged, bind-mount
│   ├── inside-build.sh       # lb config/bootstrap/chroot/binary inside the container
│   ├── test-boot.sh          # headless ISO warm-up over serial
│   ├── run-qemu.sh           # VM: shows the screen itself (GTK/SPICE/VNC), QEMU_VIEWER
│   ├── check-firmware.sh     # firmware contents in the squashfs
│   └── gen-branding.sh       # SVG → PNG for Calamares
├── config/                   # live-build tree
│   ├── common                # file with LB_* variables
│   ├── bootstrap             # file: mirror, distribution, components
│   ├── package-lists/
│   ├── hooks/
│   ├── includes.chroot/
│   ├── includes.binary/
│   └── bootloaders/
├── profiles/
│   ├── trixie.conf
│   └── sid.conf
├── builds/                   # artifacts (git-ignored)
└── docs/
    ├── PLAN.md
    └── superpowers/          # specs and plans for the superpowers workflow
```

### Key decisions

- **live-build v3** — hybrid BIOS+UEFI ISO, squashfs image, checksums out of the box
- **Calamares** — GUI installer with ext4/btrfs selection
- **The Debian installer is not included** (`--installer=false`) — saves ~1 GB
- **KDE Plasma 6 Core** — `plasma-desktop` + basic applications
- **X11 hard-wired** in the live session — Calamares is guaranteed to start
- **Building in podman** — isolation, host APT sources never leak into the image
- **Official components only** — `main contrib non-free-firmware`
- **A single profile for differences** — trixie and sid build from one config tree

### Wi-Fi coverage

The set is defined by an explicit list in
`config/package-lists/400-firmware.list.chroot` (`LB_FIRMWARE_CHROOT=false`):
Intel, Atheros/ath10k/ath11k/ath12k, MediaTek mt76, Realtek rtw88/rtw89,
Broadcom brcm80211 and b43, Marvell libertas, ZyDAS zd1211, IPW2x00, carl9170;
for graphics — amdgpu, i915/xe, Intel SOF.

The b43 firmware is downloaded by the `firmware-b43-installer` postinst script
**during the build** (the container has network access) and lands in
`/lib/firmware/b43` already inside the ISO — the user needs no network for Wi-Fi.

Deliberately excluded (hundreds of megabytes for server NICs and nvidia):
`firmware-netronome`, `firmware-nvidia-graphics`, `firmware-marvell-prestera`,
`firmware-nvidia-tesla-535-gsp`, `firmware-bnx2*`, `firmware-cavium`,
`firmware-myricom`, `firmware-netxen`, `firmware-qlogic`, `firmware-siano`,
`firmware-liquidio`, `firmware-ast`, `firmware-cirrus`, `firmware-ivtv`.
The list is checked by `make firmware`.

> **Note:** `broadcom-sta-dkms` (wl.ko) and `rtl8821cu-dkms` are absent from the
> official Debian archive — some newer chips will require a manual install after
> the system is installed.

## Installer: a local apt repository on the medium

The bootloader step in Calamares (`bootloader-config` from
`calamares-settings-debian`) installs grub into the target system using plain apt:

```
chroot $CHROOT apt-get -y install grub-efi     # UEFI
chroot $CHROOT apt-get -y install grub-pc      # BIOS
```

The live system itself has none of these packages and cannot have them: `grub-pc`
and `grub-efi-amd64` declare `Conflicts` against each other, so the image cannot
ship "both at once". And until the `sources-final` module runs, the target system's
only apt source is the medium itself: `sources-media` writes
`deb [trusted=yes] file:/run/live/medium trixie main`. If the medium is empty, the
installation stops at the bootloader:

```
Package grub-efi is not available, but is referred to by another package.
E: Package 'grub-efi' has no installation candidate
```

`config/hooks/normal/0500-purad-installer-repo.binary` downloads both sets
(`grub-pc` for BIOS, `grub-efi` + the `shim-signed` chain for UEFI), as well as
`timeshift`, `inotify-tools` and `pkexec` for btrfs snapshots. `pkexec` is
downloaded forcibly (`--reinstall`): the `packages` step removes it via
`autoremove`, and without it `apt-get install timeshift grub-btrfs pkexec` fails
entirely. `grub-btrfs` is not in Debian: the hook builds a local `.deb` from the
vendored tarball (`vendor/grub-btrfs/`, version and sha256 pinned). All of this
goes into `pool/main/`, with the index `dists/<target>/main/binary-amd64/` and a
`Release` file next to it (currently ~27 `.deb`, ~8 MB). Dependencies are computed
from the dpkg status of the **target** system (`chroot/var/lib/dpkg/status`), not
from the build container — otherwise apt would skip packages that are already
installed in the container but absent from the image. The downloaded `.deb` files
are cached in `builds/<target>/cache/purad-installer-repo/`, so rebuilding without
network access also works.

The bottom line: installation requires no internet until `sources-final`, which
restores the normal Debian mirrors. If you need to install something else offline,
just add the package name to that hook's `PACKAGE_GROUPS` (one group per line;
`grub-pc` and `grub-efi` separately, as they conflict). `make installer` warns if
the medium has no repository or no snapshot packages in it.

## btrfs snapshots

On an installation with a btrfs root, PuraD installs Timeshift and grub-btrfs. The
initial snapshot is created on the first boot of the installed system (Timeshift
does not make snapshots in live mode) and contains only the root subvolume `@`:
`/home`, `/var/log` and `/var/cache` are separate subvolumes and are not part of
the snapshot. The schedule is disabled by default — configure it yourself in
Timeshift.

- Open Timeshift: application menu → Timeshift (or `timeshift-launcher`).
- Boot into a snapshot: reboot, and in the GRUB menu choose "PuraD snapshots" →
  the snapshot you need.
- A system booted from a snapshot runs writable: changes live in RAM and are lost
  on reboot, and the snapshot itself is not modified. This is a recovery mode, not
  everyday use.
- `grub-btrfsd` updates the GRUB menu when Timeshift creates new snapshots.

Snapshots are available only on btrfs. On ext4, Timeshift and grub-btrfs are not
installed, no initramfs hooks appear, and the snapshot units are not enabled: the
`purad-first-snapshot.service` file is present in the image, but its condition on
the `/var/lib/purad/btrfs` marker is never met.

## Known installation rough edges

Verified on a live installation (`make run-install`) followed by booting from the
disk — the system installs and starts (GRUB → systemd → SDDM → Plasma). A btrfs
installation produces the layout `@` / `@home` / `@log` / `@cache` with
`compress=zstd` in `/etc/fstab`; the mount options are set in `mount.conf`
(`mountOptions`), while `fstab.conf` in Calamares 3.3 only supports
`crypttabOptions`/`tmpOptions`.

In UEFI, the installer additionally populates the fallback path `EFI/boot`
(shim + `grubx64.efi` + `mmx64.efi` + `grub.cfg`, module `purad-efi-fallback`):
the system boots even if the firmware lost its `PuraD` entry in NVRAM. Verified on
qemu/OVMF with a clean `OVMF_VARS`.

- **After installation, the VM loads the live system again.** In install mode the
  VM starts with `-boot d` (CD first), so "Reboot" in Calamares returns to the live
  session rather than the installed system. This is not an installation bug:
  `make run-installed` starts the same VM without the CD and with `-boot c`.
- **Shutting down the live system after installation used to hang for ~90 seconds** —
  fixed in stage 7. There were two causes, both in the live session's shutdown
  chain rather than in the installation:
  - `sources-media -u` from `calamares-settings-debian` did not unmount the
    bind-mount of the medium in the target root (the mount point was looked up via
    `mount | grep … | cut`, and after the bind-mount the output became multi-line,
    the path came out empty, and `umount` went to the target's root). Replaced with
    our own helper
    `config/includes.chroot/usr/share/calamares/helpers/calamares-sources-media`;
  - `live-medium-eject` from `live-tools` with `LIVE_MEDIUM_EJECT_VERBOSE=true`
    (the default) prints a prompt and waits for Enter on `/dev/console`, which
    nobody presses in a graphical session — exactly `DefaultTimeoutStopSec`.
    `config/includes.chroot/etc/live/tools.conf` disables the prompt.

  Now `systemctl poweroff` takes ~4 seconds to reach `reboot: Power down`. The
  messages `Failed to unmount /run/live/medium`, `Could not detach loop /dev/loop0`,
  `Cannot finalize remaining file systems, loop devices, continuing` still appear
  in the log — that is the medium holding the live rootfs; they do not affect
  shutdown time.

## Build cache

live-build caches bootstrap, chroot and downloaded `.deb` files in
`builds/<target>/cache/`:

- `make clean` removes the ISO and working trees but **keeps** the cache — the next
  build does not download packages again;
- `make distclean` removes everything, including the cache;
- the cache is separate for trixie and sid (different releases).

For a cache shared between profiles and projects, you can run
[apt-cacher-ng](https://wiki.debian.org/AptCacherNg) on the host:

```bash
sudo apt install apt-cacher-ng
PURAD_APT_PROXY=http://host.containers.internal:3142 make iso TARGET=trixie
```

`host.containers.internal` is the host's address from rootless podman. If the proxy
is unavailable, the build simply talks to the mirror directly.

## Rootless podman quirk: /dev in the chroot

`mknod` is not permitted in a rootless container (EPERM even with `--privileged`),
so debootstrap leaves empty regular files instead of devices in `chroot/dev/`. This
is not cosmetic: packages write to `/dev/null` as if it were a file, and one
process's write breaks the next one. That is how the KDE installation failed on
`dictionaries-common` → `aspell-autobuildhash`:

```
aspell --per-conf=/dev/null ...        # rc=0, but aspell saves the line
                                       # "/usr/bin/aspell" into per-conf
Error: /dev/null:1: The key "/usr/bin/aspell" is unknown.
```

Therefore `scripts/inside-build.sh` splits `lb build` into `lb bootstrap` →
`lb chroot` → `lb binary` and, during the stages that run postinst scripts, mounts
the container's `/dev` into `chroot/dev` via `mount --rbind` (a non-recursive
`--bind` is not enough: in the container `/dev/null` is a separate mount on top of
tmpfs, and `--bind` would substitute the placeholder file for it).

If the build fails in the middle of the chroot stage, it is easier to start the
stage from scratch:

```bash
PURAD_FORCE_CLEAN=1 make iso TARGET=trixie
```

See [PLAN.md](docs/PLAN.md) for the full description of goals, architecture and stages.
