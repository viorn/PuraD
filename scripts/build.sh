#!/bin/bash
# scripts/build.sh — сборка ISO PuraD внутри podman-контейнера
#
# Использование:
#   scripts/build.sh <trixie|sid> [-- <доп. аргументы lb build>]
#
# Быстрая проверка только конфигурации (без сборки):
#   podman run --rm --privileged -v "$PWD/builds/trixie:/work:Z" \
#       -v "$PWD/scripts:/purad-scripts:ro,Z" -w /work \
#       -e PURAD_CONFIG_ONLY=1 localhost/purad-builder:trixie \
#       bash -eux /purad-scripts/inside-build.sh trixie
#
# Что происходит:
#   1. Собирается образ purad-builder:<target> из container/Dockerfile
#      (база debian:<target>), если его ещё нет.
#   2. Готовится рабочая копия: builds/<target>/ — копия config/, profiles/,
#      VERSION. Репозиторий при этом не меняется: `lb config` перезаписывает
#      config/{common,bootstrap,chroot,binary}, и в git эти файлы не должны
#      попадать изменёнными (см. docs/PLAN.md, «Воспроизводимость»).
#   3. Контейнер с --privileged собирает образ; /work примонтирован к
#      builds/<target>/, поэтому ISO и манифесты сразу оказываются на хосте.
#   4. Кэш live-build (--cache/--cache-packages) лежит в builds/<target>/cache,
#      поэтому пересборки не качают bootstrap и пакеты заново; `make clean`
#      его удаляет.
#
# Требования: podman. Для rootless podman монтировать proc/sys в chroot
# позволяет --privileged; если он не справляется, запускать rootful podman
# (риск №4 в docs/PLAN.md).

set -euo pipefail

TARGET="${1:-}"
if [ -z "${TARGET}" ]; then
    echo "использование: $0 <trixie|sid> [-- <аргументы lb build>]" >&2
    exit 2
fi
shift || true
LB_ARGS="$*"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ ! -f "${REPO_DIR}/profiles/${TARGET}.conf" ]; then
    echo "ошибка: профиль profiles/${TARGET}.conf не найден" >&2
    echo "доступные профили: $(ls "${REPO_DIR}/profiles" | sed 's/\.conf$//' | tr '\n' ' ')" >&2
    exit 1
fi

VERSION="$(tr -d '[:space:]' < "${REPO_DIR}/VERSION")"
IMAGE="localhost/purad-builder:${TARGET}"
BASE="debian:${TARGET}"
WORK_DIR="${REPO_DIR}/builds/${TARGET}"

echo "== PuraD build =="
echo "  профиль:   ${TARGET}"
echo "  версия:    ${VERSION}"
echo "  образ:     ${IMAGE} (база ${BASE})"
echo "  рабочая:   ${WORK_DIR}"

command -v podman >/dev/null || { echo "ошибка: podman не установлен" >&2; exit 1; }

# --- 1. Образ сборщика ---
if ! podman image exists "${IMAGE}"; then
    echo "--> собираю образ сборщика ${IMAGE}"
    podman build --build-arg "BASE=${BASE}" -t "${IMAGE}" -f "${REPO_DIR}/container/Dockerfile" "${REPO_DIR}"
else
    echo "--> образ сборщика уже есть: ${IMAGE} (пересобрать: podman rmi ${IMAGE})"
fi

# --- 2. Рабочая копия конфига ---
mkdir -p "${WORK_DIR}"
echo "--> подготавливаю рабочую копию в ${WORK_DIR}"
rm -rf "${WORK_DIR}/config" "${WORK_DIR}/profiles"
cp -a "${REPO_DIR}/config" "${WORK_DIR}/config"
cp -a "${REPO_DIR}/profiles" "${WORK_DIR}/profiles"
cp -a "${REPO_DIR}/VERSION" "${WORK_DIR}/VERSION"

# --- 3. Сборка ---
# ВАЖНО: скрипты монтируются в /purad-scripts, а не в /scripts.
# live-build ищет свою библиотеку как ${LIVE_BUILD}/scripts/build.sh и при
# LIVE_BUILD непустом/совпадающем пути подхватывает чужие файлы: с /scripts
# он находил наш build.sh и сорсил его вместо своих функций.
echo "--> lb build внутри контейнера (это долго; лог: ${WORK_DIR}/build.log)"
set +e
podman run --rm --privileged \
    -v "${WORK_DIR}:/work:Z" \
    -v "${REPO_DIR}/scripts:/purad-scripts:ro,Z" \
    -w /work \
    "${IMAGE}" \
    bash -eux /purad-scripts/inside-build.sh "${TARGET}" ${LB_ARGS} \
    2>&1 | tee "${WORK_DIR}/build.log"
RC="${PIPESTATUS[0]}"
set -e

if [ "${RC}" -ne 0 ]; then
    echo "ошибка: lb build завершился с кодом ${RC} (лог: ${WORK_DIR}/build.log)" >&2
    exit "${RC}"
fi

# --- 4. Итоги ---
echo "--> артефакты в ${WORK_DIR}:"
ls -lht "${WORK_DIR}" | grep -E '\.iso|\.files|\.packages|\.contents|manifest|SHA256|sha256' || echo "  (ISO не найден — см. build.log)"
