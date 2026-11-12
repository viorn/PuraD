#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# scripts/check-firmware.sh — проверка набора прошивок в готовом ISO (Этап 5)
#
# Использование: scripts/check-firmware.sh [target]
#                make firmware TARGET=trixie
#
# Читает список путей внутри filesystem.squashfs (unsquashfs -l, без
# распаковки на диск) и проверяет, что для каждого семейства Wi-Fi/GPU есть
# хотя бы один файл. Прошивки b43 проверяются отдельно: их кладёт postinst
# firmware-b43-installer, скачивая из сети во время сборки.
#
# Код возврата 1, если хотя бы одно семейство не найдено.

set -euo pipefail

TARGET="${1:-trixie}"
VERSION="$(tr -d '[:space:]' < "$(dirname "$0")/../VERSION")"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ISO="${REPO_DIR}/builds/${TARGET}/PuraD-${TARGET}-${VERSION}-amd64.hybrid.iso"

if [ ! -f "${ISO}" ]; then
    echo "ошибка: ${ISO} не найден (сначала make iso TARGET=${TARGET})" >&2
    exit 1
fi

command -v unsquashfs >/dev/null || { echo "ошибка: нужен squashfs-tools" >&2; exit 1; }

LIST="$(mktemp)"
SQ="$(mktemp)"
trap 'rm -f "${LIST}" "${SQ}"' EXIT

# Проверяем squashfs из рабочего каталога сборки (он же попадает в ISO) —
# так не нужно распаковывать 2+ ГБ из образа. Если его нет, достаём из ISO.
if [ -f "${REPO_DIR}/builds/${TARGET}/binary/live/filesystem.squashfs" ]; then
    SQ_SRC="${REPO_DIR}/builds/${TARGET}/binary/live/filesystem.squashfs"
    echo "==> читаю список файлов из ${SQ_SRC}"
else
    echo "==> достаю squashfs из ${ISO##*/}"
    xorriso -osirrox on -indev "${ISO}" -extract /live/filesystem.squashfs "${SQ}" 2>/dev/null
    SQ_SRC="${SQ}"
fi

unsquashfs -l "${SQ_SRC}" > "${LIST}" 2>/dev/null || {
    echo "ошибка: не удалось прочитать squashfs" >&2
    exit 1
}

# check <подпись> <шаблон grep -E>
FAIL=0
check() {
    local label="$1" pattern="$2" count
    count="$(grep -cE "${pattern}" "${LIST}" || true)"
    if [ "${count}" -gt 0 ]; then
        printf '  OK   %-28s %4s файлов\n' "${label}" "${count}"
    else
        printf '  FAIL %-28s нет файлов по шаблону %s\n' "${label}" "${pattern}"
        FAIL=1
    fi
}

echo "==> Wi-Fi / Bluetooth"
check "Intel iwlwifi" 'lib/firmware/iwlwifi-[^/]*\.ucode$'
check "Atheros ath10k" 'lib/firmware/ath10k/.*/(firmware|board|otp).*\.bin$'
check "Atheros ath11k" 'lib/firmware/ath11k/.*/.*\.bin$|lib/firmware/ath11k/.*/amss\.bin$'
check "Atheros ath12k" 'lib/firmware/ath12k/.*\.bin$'
check "MediaTek mt76" 'lib/firmware/mediatek/mt79[0-9][0-9]/.*\.bin$'
check "Realtek rtw88/rtw89" 'lib/firmware/rtw8[89]/.*\.bin$'
check "Broadcom brcm80211" 'lib/firmware/brcm/brcmfmac.*\.(bin|txt)$'
check "Broadcom b43 (installer)" 'lib/firmware/b43/ucode.*\.fw$'
check "Broadcom b43legacy" 'lib/firmware/b43legacy/ucode.*\.fw$'
check "Marvell libertas" 'lib/firmware/libertas/.*\.bin$'
check "ZyDAS zd1211" 'lib/firmware/zd1211/.*$'
check "Intel ipw2x00" 'lib/firmware/ipw2[0-9]00.*\.fw$|lib/firmware/ipw2200.*\.fw$'

echo "==> Графика / звук"
check "AMD amdgpu/radeon" 'lib/firmware/amdgpu/.*\.bin$|lib/firmware/radeon/.*\.bin$'
check "Intel i915/xe" 'lib/firmware/i915/[^/]*\.bin$|lib/firmware/xe/[^/]*\.bin$'
check "Intel SOF" 'lib/firmware/intel/sof.*\.ri$'

echo "==> Регуляторный домен и стек"
check "wireless-regdb" 'lib/firmware/regulatory\.db$'

# Пакеты стека проверяем по списку из ISO (он рядом с ISO).
PKG_LIST="${REPO_DIR}/builds/${TARGET}/chroot.packages.live"
if [ -f "${PKG_LIST}" ]; then
    echo "==> Пакеты стека"
    for p in network-manager plasma-nm wpasupplicant wireless-regdb rfkill iw; do
        if grep -qE "^${p}\s" "${PKG_LIST}"; then
            printf '  OK   %s\n' "${p}"
        else
            printf '  FAIL %s не установлен\n' "${p}"
            FAIL=1
        fi
    done
fi

if [ "${FAIL}" -ne 0 ]; then
    echo "==> есть отсутствующие прошивки" >&2
    exit 1
fi
echo "==> все семейства прошивок на месте"
