# vendor/grub-btrfs

A vendored `grub-btrfs` source used to build a local `.deb` during the ISO build.
Debian does not ship a `grub-btrfs` package in any component, and the project does
not use third-party APT repositories or GPG keys.

## What's here

| File | Origin |
|---|---|
| `grub-btrfs-v4.14.tar.gz` | upstream tarball `Antynea/grub-btrfs`, tag `v4.14` |
| `initramfs-tools/hooks/grub-btrfs-overlay` | adaptation of `initramfs/ubuntu/hooks/grub-btrfs-overlay` from PR #250 |
| `initramfs-tools/scripts/local-bottom/grub-btrfs-overlay` | adaptation of `initramfs/ubuntu/scripts/local-bottom/grub-btrfs-overlay` from PR #250 |
| `build-deb.sh` | builds the local `.deb` |

## Version pinning

- Package version: `4.14-purad1`.
- tarball sha256:
  `4fe2f8a49b39e3e561fc51bbc5a0f81a7222c1e9ef8672e014e0ba3bedad20c6`.
- `build-deb.sh` verifies the sha256 before building and fails on a mismatch.

## License

`grub-btrfs` is distributed under GPL-3.0-or-later (see `LICENSE` in the tarball).
The initramfs-tools scripts from PR #250 are under the same GPL-3.0; the author of
the adaptation in that PR is Luis Marsano.

## Why the initramfs scripts are vendored separately

The upstream v4.14 release only contains initramfs scripts for Arch Linux
(mkinitcpio). For Debian/Ubuntu they live in an open PR #250 that has not been
merged upstream. Without them, booting into a read-only Timeshift snapshot ends
with a read-only root: `systemd.volatile=state` does not make the root writable
(upstream issue #331), and a separate `@var` is not needed if overlayfs is placed
over the whole root.

Differences from PR #250:

- POSIX `sh`, no bash-specific features;
- `btrfs`, `findmnt` and `mktemp` are looked up in both `/usr/bin` and `/bin` — on
  Debian with usrmerge, the `btrfs-progs` hook puts the binary in `/usr/bin`;
- on overlay failure the root is restored and boot continues read-only instead of
  panicking;
- `GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="ro systemd.mask=systemd-remount-fs.service"`
  is added to the package config: the snapshot boots read-only, and only the
  overlay provides a writable layer. `systemd-remount-fs` is masked on snapshots:
  overlayfs rejects a remount with options from `/etc/fstab`
  (`EINVAL: no changes allowed in reconfigure`), and the root is already writable.

## Build

```sh
vendor/grub-btrfs/build-deb.sh <output-dir>
```

`<output-dir>/grub-btrfs_4.14-purad1_all.deb` is placed into the local APT
repository on the medium by the
`config/hooks/normal/0500-purad-installer-repo.binary` hook.