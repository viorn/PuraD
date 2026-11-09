#!/bin/bash
# scripts/inside-build.sh — выполняется ВНУТРИ контейнера (см. scripts/build.sh)
#
# Использование: inside-build.sh <trixie|sid>
#
# Здесь — ТОЛЬКО различия релиза и вычисляемые параметры. Статические
# настройки (архитектура, образ, ядро, APT, кэш, брендинг) живут в
# config/common: live-build читает его из рабочего каталога до разбора
# аргументов `lb config`.
#
# Имена флагов соответствуют live-build 1:20250505+deb13u1 (man lb_config(1));
# сверить действующие значения — `make iso ... && grep '^LB_' builds/<target>/config/*`.

set -euo pipefail

TARGET="${1:?Использование: inside-build.sh <trixie|sid>}"

PROFILE="profiles/${TARGET}.conf"
if [ ! -f "${PROFILE}" ]; then
    echo "ошибка: профиль ${PROFILE} не найден" >&2
    exit 1
fi

# Профиль — обычный sh-файл с LB_* переменными.
. "./${PROFILE}"

: "${LB_DISTRIBUTION:?в профиле ${PROFILE} не задан LB_DISTRIBUTION}"

# Значения по умолчанию.
#
# Важно: для security-зеркал используется ${VAR-default} БЕЗ двоеточия.
# Профиль sid задаёт LB_MIRROR_SECURITY="" осознанно — у sid нет security-архива,
# и пустое значение должно означать «security выключен», а не «возьми дефолт».
MIRROR_DEBIAN="${LB_MIRROR_DEBIAN-http://deb.debian.org/debian}"
MIRROR_SECURITY="${LB_MIRROR_SECURITY-http://deb.debian.org/debian-security}"
MIRROR_BOOTSTRAP="${LB_MIRROR_BOOTSTRAP-${MIRROR_DEBIAN}}"
MIRROR_PARENT="${LB_PARENT_MIRROR_DEBIAN-${MIRROR_DEBIAN}}"
MIRROR_PARENT_SECURITY="${LB_PARENT_MIRROR_SECURITY-${MIRROR_SECURITY}}"
MIRROR_PARENT_BOOTSTRAP="${LB_PARENT_MIRROR_BOOTSTRAP-${MIRROR_PARENT}}"
ARCHIVE_AREAS="${LB_ARCHIVE_AREAS-main contrib non-free-firmware}"
PARENT_ARCHIVE_AREAS="${LB_PARENT_ARCHIVE_AREAS-${ARCHIVE_AREAS}}"
UPDATES="${LB_UPDATES-true}"

# Пустое security-зеркало = security-архива нет (случай sid). Тогда
# --security false, а пустые строки в live-build передавать нельзя — он
# считает это ошибкой, поэтому security-флаги добавляем только когда есть URL.
if [ -n "${MIRROR_SECURITY}" ]; then
    ENABLE_SECURITY=true
    MIRROR_ARGS=(
        --mirror-chroot-security "${MIRROR_SECURITY}"
        --mirror-binary-security "${MIRROR_SECURITY}"
        --parent-mirror-chroot-security "${MIRROR_PARENT_SECURITY}"
        --parent-mirror-binary-security "${MIRROR_PARENT_SECURITY}"
    )
else
    ENABLE_SECURITY=false
    MIRROR_ARGS=()
fi

# Имя ISO: PuraD-<target>-<version>, как в Makefile. Иначе live-build
# выдаст live-image-amd64.hybrid.iso.
VERSION="$(tr -d '[:space:]' < VERSION)"
IMAGE_NAME="PuraD-${TARGET}-${VERSION}"

echo "=== lb config: target=${TARGET} distribution=${LB_DISTRIBUTION} ==="
echo "  bootstrap mirror: ${MIRROR_BOOTSTRAP}"
echo "  chroot/binary mirror: ${MIRROR_DEBIAN}"
echo "  security: ${ENABLE_SECURITY} (${MIRROR_SECURITY:-<нет security-архива>})"
echo "  updates: ${UPDATES}"
echo "  archive-areas: ${ARCHIVE_AREAS}"
echo "  image-name: ${IMAGE_NAME}"

lb config \
    --architecture amd64 \
    --mode debian \
    --distribution "${LB_DISTRIBUTION}" \
    --archive-areas "${ARCHIVE_AREAS}" \
    --parent-archive-areas "${PARENT_ARCHIVE_AREAS}" \
    --mirror-bootstrap "${MIRROR_BOOTSTRAP}" \
    --mirror-chroot "${MIRROR_DEBIAN}" \
    --mirror-binary "${MIRROR_DEBIAN}" \
    --parent-mirror-bootstrap "${MIRROR_PARENT_BOOTSTRAP}" \
    --parent-mirror-chroot "${MIRROR_PARENT}" \
    --parent-mirror-binary "${MIRROR_PARENT}" \
    "${MIRROR_ARGS[@]}" \
    --security "${ENABLE_SECURITY}" \
    --updates "${UPDATES}" \
    --image-name "${IMAGE_NAME}"

echo "=== Effective config (LB_*) ==="
grep -h '^LB_' config/common config/bootstrap config/chroot config/binary 2>/dev/null | sort || true

echo "=== package_lists ==="
ls -1 config/package_lists/chroot/ 2>/dev/null || echo "(пусто)"

# Быстрая проверка синтаксиса конфига без долгой сборки:
#   podman run ... -e PURAD_CONFIG_ONLY=1 ...
if [ "${PURAD_CONFIG_ONLY:-0}" = "1" ]; then
    echo "=== PURAD_CONFIG_ONLY=1: останавливаюсь после lb config ==="
    exit 0
fi

echo "=== lb build ==="
lb build

echo "=== артефакты ==="
ls -lh ./*.iso ./*.sha256 ./SHA256SUMS ./manifest* 2>/dev/null || true
