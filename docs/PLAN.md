# PuraD — project plan

> **The working name of the distribution is PuraD.** The name is a working one: it may stay,
> or it may be replaced later. The repository currently lives in `deked/`, so we do not change the directory path
> or the build directory name; for the brand inside the image (Calamares, bootloader,
> `/etc/os-release`) we use PuraD, and when renaming we only change that.

A live distribution based on pure Debian: a liveCD with KDE Plasma, installation to ext4/btrfs
out of the box, without third-party repositories. The first target is Debian 13 (trixie), then a profile
for sid.

## 1. Goals and principles

- **Pure Debian.** Only official archive components (`main`, `contrib`,
  `non-free-firmware`). No `config/archives/*` in live-build, no third-party
  GPG keys. `non-free-firmware` is an official Debian component since release 12,
  using firmware from it does not violate purism.
- **Reproducibility.** All live-build configs are stored in git; the build produces an identical
  result on any machine with the same profile and archive snapshot.
- **Build isolation.** Building only inside a container (`podman`), host APT sources
  must not have any chance of getting into the image.
- **One profile of differences.** trixie and sid are built with a single config tree; release
  divergences are factored out into `profiles/<codename>.conf`.

## 2. Key decisions

| Area | Decision | Rationale |
|---|---|---|
| Build tool | `live-build` (v3, `lb config`/`lb build`) | Official Debian tool: hybrid BIOS+UEFI ISO, live-boot + overlayfs, checksums, manifests out of the box |
| Installer | Calamares 3.3.x | GUI selection of ext4/btrfs, btrfs-subvolume layout `@`/`@home`, branding; customizing d-i for this is incomparably more expensive |
| debian-installer | we do not include it (`--installer=false`) | saves ~1 GB and one layer of complexity |
| Environment | KDE Plasma 6 (Core set) | `plasma-desktop` + basic applications, without `kde-full` |
| live-CD session | **X11, hard-coded** | more reliable than Wayland on arbitrary hardware/drivers; Calamares is guaranteed to start (pkexec/polkit, DISPLAY). On the installed disk Wayland remains available |
| Archive components | `main contrib non-free-firmware` | contrib is needed for the b43 glue; non-free-firmware — for Wi-Fi/GPU/NVMe |
| Wi-Fi | maximum coverage with firmware packages | without firmware in the live-CD it is impossible to fix the network on a live system |
| Build | `podman` + `debian:trixie` / `debian:sid` | the live-build/dpkg version matches the target release; the host is not polluted |
| Sid | apt pinning to a `snapshot.debian.org` snapshot | sid at an arbitrary moment may be unbuildable; a snapshot provides reproducibility |
| Distribution name | **PuraD** (working) | may change; the brand is isolated in `branding/`, `/etc/os-release` and the bootloader theme, renaming is a single edit |
| btrfs snapshots | Timeshift + grub-btrfs, overlayfs in initramfs | btrfs only; booting into an RO snapshot actually works, `@var` is not needed (stage 10) |

### Core set (v1)

`plasma-workspace`, `sddm`, `dolphin`, `konsole`, `firefox-esr`, `systemsettings`,
`plasma-nm`, `xdg-desktop-portal-kde`, `okular`, `ark`, fonts, Breeze.
Without persistence, Secure Boot, arm64 and our own APT repository — those are v2 candidates.

### Wi-Fi coverage

Packages: `firmware-iwlwifi`, `firmware-atheros`, `firmware-ath9k-htc`,
`firmware-brcm80211`, `firmware-misc-nonfree` (rtw88/rtw89/mt76), `firmware-realtek`,
`firmware-mediatek` (mt7921/mt7925), `firmware-ipw2x00`, `firmware-zd1211`,
`firmware-libertas`, `firmware-carl9171`, plus the contrib glue
`firmware-b43-installer` / `firmware-b43legacy-installer`, and the stack
`iw wpasupplicant wireless-regdb rfkill network-manager plasma-nm`.

Constraints (deliberate):

- `broadcom-sta-dkms` (wl.ko) and `rtl8821cu-dkms` are absent from the official Debian
  archive — some new chips will require manual installation after the install;
  we do not put them in the image so as not to violate "pure Debian".
- `firmware-b43-installer` downloads the firmware in postinst: it runs during
  the build (the container has network), so the firmware is already in the ISO and
  there is no need to vendor binaries into `includes.chroot`.

### Pinning X11 in the live session

- SDDM autologin into the `plasmax11` session (`/usr/share/xsessions/plasmax11.desktop`,
  `/usr/bin/startplasma-x11`, the unit `plasma-workspace-x11.target` — present
  in `plasma-workspace 6.3.6-2`).
- Selection of the Wayland session is removed from the greeter (in live mode).
- The restriction applies only to the live session; on the installed disk SDDM offers
  both sessions, and the installer asks which one to make the default session
  (stage 7, `packagechooser@session`).

Implementation — a live-config component
`config/includes.chroot/usr/lib/live/config/0086-purad-live-x11`: it runs
after the stock `0085-sddm` and overrides it, writing
`/etc/sddm.conf.d/zz-purad-live-x11.conf` (`[Autologin] Session=plasmax11`)
and renaming `/usr/share/wayland-sessions/*.desktop` to `*.disabled`.
The stock `0085-sddm` selects `Session=` by `realpath $(which x-session-manager)`,
and `x-session-manager` may point to a Wayland session, so one cannot rely
on it.

## 3. Repository structure

```
deked/                        # repository directory; the distribution name is PuraD
├── Makefile                  # make iso TARGET=trixie|sid, make clean
├── VERSION
├── container/
│   └── Dockerfile            # debian:{trixie,sid} + live-build and build dependencies
├── scripts/
│   ├── build.sh              # podman --privileged, bind-mount, apt cache volume
│   ├── inside-build.sh       # lb config/bootstrap/chroot/binary inside the container
│   ├── test-boot.sh          # qemu warm-up of the ISO (BIOS and UEFI)
│   └── check-firmware.sh     # firmware composition in squashfs (make firmware)
├── config/                   # live-build tree
│   ├── common                # LB_ARCHITECTURES, LB_MODE, LB_BOOTLOADER, ...
│   ├── bootstrap             # mirror, distribution, components
│   ├── package-lists/        # 000-base, 100-kde, 400-firmware
│   ├── preseed/              # debconf answers (firmware-ipw2x00 license)
│   ├── hooks/                # chroot hooks: branding, configs, systemd
│   ├── includes.chroot/      # /etc/skel KDE, /etc/calamares, polkit, live-config
│   ├── includes.binary/      # bootloader theme
│   └── bootloaders/          # grub-efi + isolinux
├── profiles/
│   ├── trixie.conf
│   └── sid.conf              # only release differences
├── builds/                   # artifacts (in .gitignore)
└── docs/
    ├── PLAN.md               # this file
    ├── build.md              # step-by-step build instructions
    └── checklist-release.md  # pre-release checks
```

Principles: one config — two releases; no `config/archives/`; iterative build
through the live-build bootstrap/chroot cache.

## 4. Stages

### Stage 1. Project skeleton

git init, directories, `VERSION`, `Makefile`, `.gitignore`, README describing
the build architecture.

**Done when:** `make help` works, the directory structure is in place.

### Stage 2. Container builder

`container/Dockerfile`: `debian:trixie`/`debian:sid` + `live-build`, `debootstrap`,
`squashfs-tools`, `xorriso`, `isolinux`, `grub-efi-amd64-bin`, `syslinux-common`,
`mtools`, `dosfstools`, `git`, `ca-certificates`.
`scripts/build.sh`: `podman --privileged`, bind-mount of the project, volume for the apt cache,
artifacts in `builds/`.

**Done when:** `lb config && lb build` runs inside the container
(for now at least on a minimal config).

### Stage 3. Minimal live image

`config/common`, `config/bootstrap`: mirror `deb.debian.org`, components
`main contrib non-free-firmware`, `--installer=false`, `--mode debian`.
Packages: `linux-image-amd64`, `live-boot`, `live-config-systemd`.
Boot check in qemu (if missing — install `qemu-system-x86` and `ovmf`):
`scripts/test-boot.sh <target> --all` (also `make test`). Added to bootappend:
`console=tty0 console=ttyS0,115200n8`, so that the live session is visible in headless qemu;
login — live-config defaults (`user` / `live`).

**Done when:** the ISO boots in qemu (BIOS and UEFI) to the live session shell.
Both modes verified: `make test TARGET=trixie`.

### Stage 4. KDE Plasma 6 (Core) + X11

KDE package lists, a hook for live-session autologin with X11 pinning
(SDDM `Session=plasmax11`, hide session selection), disabling unwanted services
(baloo, krdisplaydrc, etc. as appropriate), `/etc/skel` with Plasma presets
(panel, Breeze theme, no first-run wizard).

**Done when:** the live image boots into Plasma on X11 with autologin;
`echo $XDG_SESSION_TYPE` → `x11`; Wayland is unavailable in the live-mode session list.

The Core set and X11 pinning are described in the sections "Core set" and "Pinning X11
in the live session". Verified by `make test TARGET=trixie` (BIOS and UEFI):
SDDM autologins `user` into the `Type=x11` session (`/usr/share/xsessions/plasmax11.desktop`),
`/usr/share/wayland-sessions/plasma.desktop` is renamed to `.disabled`.
Plasma presets in `/etc/skel` — only `baloofilerc`; the panel/theme/first-run
wizard are not configured yet.

### Stage 5. Maximum Wi-Fi coverage

See the "Wi-Fi coverage" section. Check: unpacking `filesystem.squashfs` from the ISO and
the presence of the expected `.rbf/.fw/.dat` in `/lib/firmware`; in the live session `iw dev` sees
a wireless interface (in qemu — via a usb-wifi passed-through device or
a check by the squashfs contents).

**Done when:** all firmware from the list is in the image, NetworkManager brings up Wi-Fi
in the live session.

Implementation: `config/package-lists/400-firmware.list.chroot` + the wireless stack,
`LB_FIRMWARE_CHROOT=false` (otherwise live-build pulls all `firmware-*` from the archive,
including server NICs and nvidia). b43 is covered by the `firmware-b43*-installer` packages:
their postinst downloads the firmware during the build, the files are already in the ISO.
Check — `make firmware TARGET=trixie` (`scripts/check-firmware.sh`):
reads the file list of `filesystem.squashfs` and requires at least one file for
each family (iwlwifi, ath10k/11k/12k, mt76, rtw88/89, brcm80211, b43,
libertas, zd1211, ipw2x00, amdgpu, i915/xe, SOF) plus the stack packages.

### Stage 6. Calamares in the live image

As a basis — the configs of the `calamares-settings-debian` package, on top — our own
`settings.conf` and module sequence, `PuraD` branding (working name; when
renaming, only `branding/<name>.conf` and the shortcut change), a polkit rule,
an "Install PuraD" shortcut on the desktop.

**Done when:** Calamares launches from the live session (X11) without manual password
entry in the terminal, and proceeds up to the partitioning step.

**Implementation:**

- `config/package-lists/300-installer.list.chroot` — `calamares` +
  `calamares-settings-debian`; the module sequence is taken from the distribution,
  comments translated, branding switched to `purad`
  (`config/includes.chroot/etc/calamares/settings.conf`);
- branding — `config/includes.chroot/etc/calamares/branding/purad/`
  (`branding.desc`, `show.qml` with `slideshowAPI: 2`, PNG). The sources are
  `assets/branding/*.svg`, rendered to PNG by `scripts/gen-branding.sh` (QML
  does not support SVG);
- `usr/lib/live/config/0087-purad-calamares` — a polkit rule for the live user
  for **two** action ids: `org.freedesktop.policykit.exec` and
  `com.github.calamares.calamares.pkexec.run` (Calamares declares its own
  action, generic rules for pkexec are not enough);
- `usr/bin/purad-installer` — a wrapper: hides the live `/etc/fstab`
  (`# UNCONFIGURED FSTAB FOR BASE SYSTEM`) and runs `pkexec /usr/bin/calamares`;
- the "Install PuraD" shortcut: `usr/share/applications/purad-install.desktop` +
  `usr/bin/purad-installer-icon` from `/etc/xdg/autostart`, which places it on
  the desktop only when booting from the medium (`/run/live`);
- **a local apt repository on the medium** — `config/hooks/normal/0500-purad-installer-repo.binary`.
  The `bootloader-config` step installs grub with a regular `apt-get install grub-efi|grub-pc`
  from the target system, and before the `sources-final` module the only source is the
  medium itself. Without `pool/` the installation fails with
  `E: Package 'grub-efi' has no installation candidate`;
- `scripts/test-boot.sh --installer` — checks the launch of Calamares from the live session
  via the serial console (pkexec, XAUTHORITY, absence of "Not authorized").

### Stage 7. ext4/btrfs installation

- `partition.conf`: `defaultFileSystemType: ext4`, btrfs in the list,
  `initialSwapChoice: none`, EFI partition under UEFI;
- `mount.conf`: btrfs subvolumes `@` → `/`, `@home` → `/home`, `@log`,
  `@cache`; mount options (`noatime`, `compress=zstd`, `umask=0077` for EFI);
- `fstab.conf`: only what Calamares 3.3 reads (`crypttabOptions`,
  `tmpOptions`) — mount options come from `mount.conf`;
- `bootloader.conf`: GRUB for BIOS and UEFI;
- remove the shutdown hang of the live system after installation.

**Done when:** test installations in qemu on btrfs and ext4 complete;
after reboot: correct `fstab`, subvolume layout (`@`, `@home`),
the bootloader starts, `/home` on a separate subvolume.

**Implementation** (`config/includes.chroot/etc/calamares/modules/*.conf`):
Debian does not ship `partition.conf`, so it is ours; the other three are copies
of the `calamares-settings-debian` configs without extra keys.

- GPT on BIOS is **not forced**: `requiredPartitionTableType` in `partition.conf`
  only filters already existing tables and does not affect autopartitioning —
  `PartitionActions::doAutopartition` hard-codes `partType = isEfi ? gpt : msdos`.
  GPT on BIOS would require a `bios_grub` partition, which Calamares does not create.
- `fstab.conf` is reduced to `crypttabOptions` + `tmpOptions`: `mountOptions` and
  `ssdExtraMountOptions` are Calamares 3.2, in 3.3 they are not read (the
  `fstab.schema.yaml` schema with `additionalProperties: false` complained about them). The options
  are taken from `mountOptions` in `mount.conf` via `mountOptionsList` in global storage.
- `config/includes.chroot/usr/share/calamares/helpers/calamares-sources-media` —
  a replacement for the same-named helper from `calamares-settings-debian` (see below).
- `config/includes.chroot/etc/live/tools.conf` — `LIVE_MEDIUM_EJECT_VERBOSE=false`.
- our own Calamares module `purad-efi-fallback` (a step right after `bootloader`) —
  completes the UEFI fallback boot path. With
  `installEFIFallback: true`, Calamares copies only the bootloader itself into `EFI/boot`
  (`grubx64.efi` → `bootx64.efi`) and does not put `grub.cfg` there. Firmware that lost
  the NVRAM entry dropped into the `grub>` prompt (verified on qemu with a clean
  `OVMF_VARS`). The module lays out `EFI/boot` as `grub-install --removable`:
  shim as the first stage, `grubx64.efi`, `mmx64.efi` and `grub.cfg` from the bootloader
  directory (`EFI/PuraD`).
- selection of the default Plasma session: the `packagechooser@session` page
  (`packagechooser-session.conf`, Wayland/X11) in the `show` phase and the module
  `purad-session` in `exec` right after `displaymanager`. There is no "default
  session" key in `/etc/sddm.conf`; SDDM 0.21 takes the preselection from
  `[Last] Session=` in `/var/lib/sddm/state.conf` (`sddm-state.conf(5)`:
  "preselected when the login screen shows up") and after a successful login
  updates it itself (`RememberLastSession`). The module writes
  `Session=plasmax11.desktop` or `plasma.desktop` and the `sddm` owner
  from `/etc/passwd` of the **target** system (the uid in live and in the target need not
  match). The `packagechooser` instance is needed because the global
  storage key is `packagechooser_<instance id>`, and Calamares 3.3 does not read
  the `id:` key inside the config.

**Shutdown hang — two independent causes:**

1. `sources-media -u` did not unmount the bind mount of the medium. The Debian helper looked for
   the mount point via `mount | grep $path | cut -f3 -d' '`; after the
   bind mount in the chroot the output became multiline and `MEDIUM_PATH`
   turned out to be empty, so `-u` executed `umount $CHROOT/` (the target root,
   busy) and the bind mount remained alive until shutdown itself. Our helper
   looks for the point via `mountpoint -q` over a list of known paths and unmounts exactly
   `$CHROOT$MEDIUM_PATH`.
2. `live-medium-eject` (from `live-tools`, invoked by
   `/usr/lib/systemd/system-shutdown/live-tools.shutdown`) with
   `LIVE_MEDIUM_EJECT_VERBOSE=true` (the default) prints a prompt and does
   `read x < /dev/console` — waits for Enter, which no one in a graphical session will
   press. Via `DefaultTimeoutStopSec` this gave exactly ~90 s (in measurements —
   up to 206 s). `tools.conf` disables the prompt; the tray still opens
   in the background.

**Verified** (qemu, BIOS and UEFI, `qemu-img`/`debugfs`/`mtools` on the disk
image and booting the installed system):

- ext4: `/etc/fstab` → `UUID=… / ext4 defaults,noatime 0 1`,
  `grub.cfg` → `menuentry 'PuraD GNU/Linux'`, `GRUB_DISTRIBUTOR='PuraD'`;
  the disk — `dos`, one 24 GiB partition;
- btrfs: subvolumes `@`, `@home`, `@log`, `@cache`; `/etc/fstab`:
  `subvol=/@`, `subvol=/@home`, `subvol=/@log`, `subvol=/@cache` —
  all with `defaults,noatime,compress=zstd`, `pass=0`; the filesystem
  is mounted with `zstd` (visible in `dmesg`);
- UEFI (`OVMF`): GPT, ESP 512 MiB FAT32 (`/boot/efi` with `defaults,umask=0077`),
  `/etc/fstab` with the same `subvol=/@…,compress=zstd`; on the ESP —
  `EFI/PuraD/{shimx64,grubx64,mmx64,fbx64}.efi` + `grub.cfg` with
  `prefix=($root)'/@/boot/grub'` and a populated `EFI/boot`
  (`bootx64.efi`=shim, `grubx64.efi`, `mmx64.efi`, `grub.cfg`);
  an entry `PuraD` → `\EFI\PuraD\shimx64.efi` is created in NVRAM;
- after reboot: GRUB → systemd → SDDM (Plasma/Wayland) → Plasma —
  verified in BIOS and in UEFI, in UEFI twice: with a preserved NVRAM (the entry
  `PuraD`) and with a reset NVRAM (boot via `\EFI\BOOT\BOOTX64.EFI`);
- shutdown of the live session after installation: from `systemctl poweroff` to
  `reboot: Power down` — ~4 s instead of 90–206 s. Cosmetic
  `Failed to unmount /run/live/medium`, `Could not detach loopback /dev/loop0` remain
  (the live rootfs itself holds the medium) — they do not affect the shutdown time.

### Stage 8. sid profile

`profiles/sid.conf`, build in the `debian:sid` container, apt pinning to a
`snapshot.debian.org` snapshot (via `config/archives/*.pref.chroot` + pin by origin;
live-build does not support `config/apt/preferences.chroot`).
Resolving divergences: package names of KDE, live-boot, calamares.

**Done when:** the sid ISO boots, Calamares completes the installation the same way as trixie.

### Stage 9. Reproducible cycle

Targets `make iso TARGET=trixie|sid`, `make clean`; sha256 sums and a manifest package
in `builds/`; `docs/build.md` and `docs/checklist-release.md`.

**Done when:** a full rebuild from scratch on a clean machine reproduces the result
according to the docs instructions without manual steps outside the Makefile.

### Stage 10. btrfs snapshots (Timeshift + grub-btrfs)

- btrfs only: the Calamares module `purad-snapshots` after `packages`
  determines the filesystem of the target root; on ext4 it exits without installing
  or enabling anything.
- `timeshift` and `pkexec` are downloaded from Debian `main` when building the ISO.
  `pkexec` is needed for the graphical launch of Timeshift and is pulled forcibly:
  the `packages` step removes it with `autoremove`, and an atomic `apt-get install`
  without it would not install Timeshift either. `grub-btrfs` is absent in
  Debian, so upstream v4.14 is vendored into
  `vendor/grub-btrfs/` (the tarball sha256 is pinned) and built into a local
  `.deb` by the `0500-purad-installer-repo.binary` hook. There are no third-party APT repositories
  or GPG keys; this is the only explicit exception to the "pure
  Debian" principle.
- The initial snapshot is created by `purad-first-snapshot.service` on the first boot
  of the installed system: Timeshift in live mode refuses to create
  snapshots (`boot=live` in `/proc/cmdline`). The snapshot contains only `@`;
  `@home`, `@log`, `@cache` are separate subvolumes. The schedule is
  disabled by default.
- Booting into a snapshot: `grub-btrfsd` (`--timeshift-auto`) updates the GRUB menu,
  and the initramfs-tools hook from the package brings up overlayfs on top of the read-only
  snapshot. The system starts writable, changes live in RAM and disappear on
  reboot, the snapshot itself does not change. A separate `@var` is not needed.
- The hook is an adaptation of upstream PR #250 (GPL-3.0, not merged into upstream; only
  Arch scripts are in the release). Therefore booting into a snapshot must be
  verified in qemu on trixie; the fallback is a separate `@var` as a separate task.

**Done when:** on btrfs in qemu after installation there is an initial snapshot,
GRUB has snapshot entries, booting into a snapshot gives `findmnt -no FSTYPE /` =
`overlay`; on ext4 Timeshift and grub-btrfs are not installed, initramfs hooks
do not appear, snapshot units are not enabled.

## 5. Risks

1. **Calamares + Wayland** — resolved by pinning X11 in the live session (Stage 4).
2. **ISO size** ~4–5 GB due to the firmware set. Fallback: a `core-lite` variant.
3. **Sid mid-transition** — pinning to snapshot.debian.org (Stage 8), otherwise the build
   is not reproducible.
4. **Rootless podman**: `--privileged` may not allow mounting proc/sys into the chroot.
   Fallback: rootful podman. A separate trap — `mknod` in a rootless container
   is forbidden, so there are no devices in `chroot/dev` and `/dev/null` is a regular file;
   it is fixed by `mount --rbind /dev chroot/dev` for the duration of the chroot stage
   (`scripts/inside-build.sh`, details in the README).
5. **b43**: postinst requires network; we pin the firmware in includes (Stage 5).
6. **Plasma 6 in sid**: transitional versions (6.3 → 6.x) may change dependencies;
   it is fixed by snapshot pinning.
7. **grub-btrfs and the overlayfs hook — not from Debian.** The vendored grub-btrfs
   v4.14 and initramfs scripts from the unmerged upstream PR #250. Verification of booting
   into a snapshot on trixie in qemu is mandatory; the fallback is a separate `@var`
   (a separate task).

## 6. Versions in trixie (at the time of planning)

- live-build `1:20250505+deb13u1`, live-boot `1:20250815~deb13u1`,
  live-config `11.0.5`
- calamares `3.3.14-1` (Qt6, libkpmcore12), calamares-settings-debian `13.0.13-1`
- plasma-desktop `4:6.3.6-1`, plasma-workspace `4:6.3.6-2`, sddm `0.21.0+git20250502`
- firmware `20250410-2`
