#!/bin/bash
# scripts/test-snapshots-deb.sh — проверка вендоренного grub-btrfs.
#
# Собирает локальный .deb тем же скриптом, что и хук 0500 при сборке ISO,
# и проверяет метаданные, состав пакета и синтаксис initramfs-скриптов.
# Не требует podman, root и сети: только dpkg-deb и tar.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILDER="${REPO_DIR}/vendor/grub-btrfs/build-deb.sh"
HOOK="${REPO_DIR}/vendor/grub-btrfs/initramfs-tools/hooks/grub-btrfs-overlay"
BOTTOM="${REPO_DIR}/vendor/grub-btrfs/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay"

OUT="$(mktemp -d)"
trap 'rm -rf "${OUT}"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -x "${BUILDER}" ] || fail "нет исполняемого ${BUILDER}"

echo "==> собираю grub-btrfs в ${OUT}"
"${BUILDER}" "${OUT}"

DEB="${OUT}/grub-btrfs_4.14-purad1_all.deb"
[ -f "${DEB}" ] || fail "сборщик не создал ${DEB}"

echo "==> метаданные"
[ "$(dpkg-deb -f "${DEB}" Package)" = "grub-btrfs" ] || fail "Package"
[ "$(dpkg-deb -f "${DEB}" Version)" = "4.14-purad1" ] || fail "Version"
[ "$(dpkg-deb -f "${DEB}" Architecture)" = "all" ] || fail "Architecture"

DEPENDS="$(dpkg-deb -f "${DEB}" Depends)"
for dep in btrfs-progs grub-common inotify-tools initramfs-tools; do
    case " ${DEPENDS} " in
        *" ${dep} "*) ;;
        *" ${dep},"*|*", ${dep} "*) ;;
        *) fail "в Depends нет ${dep}: ${DEPENDS}" ;;
    esac
done

echo "==> состав"
CONTENTS="$(dpkg-deb -c "${DEB}")"
for path in \
    ./etc/grub.d/41_snapshots-btrfs \
    ./etc/default/grub-btrfs/config \
    ./usr/bin/grub-btrfsd \
    ./usr/lib/systemd/system/grub-btrfsd.service \
    ./etc/initramfs-tools/hooks/grub-btrfs-overlay \
    ./etc/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay; do
    grep -q "${path}\$" <<< "${CONTENTS}" || fail "в пакете нет ${path}"
done

echo "==> конфиг GRUB"
CONFIG="$(dpkg-deb --fsys-tarfile "${DEB}" | tar -xO ./etc/default/grub-btrfs/config)"
grep -q 'GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="ro systemd.mask=systemd-remount-fs.service"' \
    <<< "${CONFIG}" || fail "нет ro и маски systemd-remount-fs для снимков"

echo "==> initramfs-скрипты"
[ -f "${HOOK}" ] || fail "нет ${HOOK}"
[ -f "${BOTTOM}" ] || fail "нет ${BOTTOM}"
sh -n "${HOOK}" || fail "синтаксис ${HOOK}"
sh -n "${BOTTOM}" || fail "синтаксис ${BOTTOM}"

echo "PASS: grub-btrfs 4.14-purad1 собран и проверен"