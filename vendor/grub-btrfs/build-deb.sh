#!/bin/sh
# SPDX-FileCopyrightText: 2026 PuraD
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build-deb.sh — собрать локальный .deb grub-btrfs из вендоренного тарбола.
#
# Использование:
#   vendor/grub-btrfs/build-deb.sh <output-dir>
#
# Почему не `make install` upstream:
#   * Makefile требует root и сам вызывает grub-mkconfig, если найден
#     /boot/grub/grub.cfg. В live-сборке это лишнее и опасно.
#   * Нам нужен предсказуемый набор файлов и режимы прав.
#
# Пакет не содержит maintainer-скриптов: update-grub/update-initramfs в
# live-chroot не запускаются. initramfs перегенерирует штатный модуль
# Calamares `initramfs`, который идёт после `packages`.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${1:?использование: build-deb.sh <output-dir>}

VERSION=4.14-purad1
SRC_DIR=grub-btrfs-4.14
TARBALL="$HERE/grub-btrfs-v4.14.tar.gz"
SHA256=4fe2f8a49b39e3e561fc51bbc5a0f81a7222c1e9ef8672e014e0ba3bedad20c6

[ -f "$TARBALL" ] || {
    echo "build-deb.sh: нет $TARBALL" >&2
    exit 1
}

GOT=$(sha256sum "$TARBALL" | awk '{print $1}')
[ "$GOT" = "$SHA256" ] || {
    echo "build-deb.sh: sha256 не совпал" >&2
    echo "  ожидался: $SHA256" >&2
    echo "  получен:  $GOT" >&2
    exit 1
}

mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

tar -xzf "$TARBALL" -C "$WORK"
SRC="$WORK/$SRC_DIR"
[ -d "$SRC" ] || {
    echo "build-deb.sh: в тарболе нет $SRC_DIR" >&2
    exit 1
}

PKG="$WORK/pkg"
mkdir -p "$PKG/DEBIAN"

install -Dm755 "$SRC/41_snapshots-btrfs"       "$PKG/etc/grub.d/41_snapshots-btrfs"
install -Dm644 "$SRC/config"                   "$PKG/etc/default/grub-btrfs/config"
install -Dm744 "$SRC/grub-btrfsd"              "$PKG/usr/bin/grub-btrfsd"
install -Dm644 "$SRC/grub-btrfsd.service"      "$PKG/usr/lib/systemd/system/grub-btrfsd.service"
install -Dm644 "$SRC/manpages/grub-btrfs.8.man"  "$PKG/usr/share/man/man8/grub-btrfs.8"
install -Dm644 "$SRC/manpages/grub-btrfsd.8.man" "$PKG/usr/share/man/man8/grub-btrfsd.8"
install -Dm644 "$SRC/LICENSE"                  "$PKG/usr/share/doc/grub-btrfs/LICENSE"
install -Dm644 "$SRC/README.md"                "$PKG/usr/share/doc/grub-btrfs/README.md"
install -Dm644 "$SRC/initramfs/readme.md"      "$PKG/usr/share/doc/grub-btrfs/initramfs-overlayfs.md"

# initramfs-tools: overlay поверх read-only снимка (адаптация upstream PR #250).
install -Dm755 "$HERE/initramfs-tools/hooks/grub-btrfs-overlay" \
    "$PKG/etc/initramfs-tools/hooks/grub-btrfs-overlay"
install -Dm755 "$HERE/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay" \
    "$PKG/etc/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay"

# Пункты снимков в GRUB должны грузиться с ro: снимок неизменяем, а
# initramfs-скрипт поднимет поверх него writable overlay.
printf '\n# PuraD: boot snapshots read-only; the initramfs overlay makes them writable.\nGRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="ro"\n' \
    >> "$PKG/etc/default/grub-btrfs/config"

SIZE=$(du -sk "$PKG" | awk '{print $1}')

cat > "$PKG/DEBIAN/control" <<EOF
Package: grub-btrfs
Version: $VERSION
Architecture: all
Maintainer: PuraD <purad@localhost>
Installed-Size: $SIZE
Section: admin
Priority: optional
Depends: btrfs-progs, grub-common, bash (>= 4), gawk | mawk, inotify-tools, initramfs-tools
Description: GRUB menu entries for btrfs snapshots
 grub-btrfs adds a GRUB submenu with btrfs snapshots created by Timeshift
 and other tools, so a read-only snapshot can be booted.
 .
 This package is built locally for PuraD from the upstream v4.14 source.
 It also installs initramfs-tools scripts that mount an overlayfs over a
 read-only snapshot at boot, making the session writable without changing
 the snapshot.
EOF

dpkg-deb --build --root-owner-group "$PKG" "$OUT/grub-btrfs_${VERSION}_all.deb" >/dev/null
echo "P: собран $OUT/grub-btrfs_${VERSION}_all.deb"