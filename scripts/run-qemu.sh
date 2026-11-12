#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# scripts/run-qemu.sh — интерактивный запуск собранного ISO в qemu.
#
# Использование:
#   scripts/run-qemu.sh [trixie|sid] [--uefi] [--disk [SIZE]] [--installed]
#                       [--mem MiB] [--tcg] [--viewer MODE] [--dry-run]
#
# Опции:
#   --uefi        загрузить через UEFI (OVMF); по умолчанию — BIOS
#   --disk[=SIZE] добавить пустой диск для проверки установки (по умолчанию 20G,
#                 qcow2 в builds/<target>/run/disk.qcow2, создаётся один раз)
#   --installed   загрузиться с уже установленного диска: без CD и с -boot c.
#                 Нужно после установки: пока CD в приводе и -boot d, машина
#                 снова грузит live-систему, а не установленную.
#   --mem MiB     память (по умолчанию 3072 — Plasma комфортнее с 3 ГБ)
#   --tcg         без KVM (медленно, но работает в контейнерах/без /dev/kvm)
#   --viewer MODE чем показывать экран VM:
#                   auto (по умолчанию) — самое отзывчивое из доступного:
#                          окно SPICE (remote-viewer), иначе GTK, иначе VNC;
#                          без $DISPLAY/$WAYLAND_DISPLAY — только VNC;
#                   gtk | spice | vnc | none
#                 VNC слушает 127.0.0.1:5900 и сам открывает `krdc`, если он есть.
#   --dry-run     показать выбранный viewer и команду qemu, ничего не запуская
#   -h|--help     эта справка
#
# Отличие от scripts/test-boot.sh: тот прогоняет headless-проверки по serial,
# а этот запускает обычную виртуальную машину с графикой — посмотреть глазами,
# потыкать Calamares, проверить установку на диск.
#
# Вход в live-систему: user / live (умолчания live-config).

set -euo pipefail

TARGET="trixie"
UEFI=0
USE_DISK=0
INSTALLED=0
DISK_SIZE="20G"
MEM=3072
ACCEL=(-accel kvm)
VIEWER="auto"
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        trixie|sid)
            TARGET="$1"
            ;;
        --uefi)
            UEFI=1
            ;;
        --disk)
            USE_DISK=1
            ;;
        --disk=*)
            USE_DISK=1
            DISK_SIZE="${1#--disk=}"
            ;;
        --installed)
            USE_DISK=1
            INSTALLED=1
            ;;
        --mem)
            MEM="${2:?--mem требует значение}"
            shift
            ;;
        --tcg)
            ACCEL=(-accel tcg,thread=multi)
            ;;
        --viewer)
            VIEWER="${2:?--viewer требует значение}"
            shift
            ;;
        --viewer=*)
            VIEWER="${1#--viewer=}"
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        -h|--help)
            # Справка — от строки 2 до строки "# Отличие" (не включая её).
            sed -n '2,/^# Отличие/p' "$0" | sed '$d'
            exit 0
            ;;
        *)
            echo "неизвестный аргумент: $1" >&2
            exit 2
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_DIR}/VERSION")"
ISO="${REPO_DIR}/builds/${TARGET}/PuraD-${TARGET}-${VERSION}-amd64.hybrid.iso"
RUN_DIR="${REPO_DIR}/builds/${TARGET}/run"

if [ "${DRY_RUN}" -eq 0 ] && [ "${INSTALLED}" -eq 0 ] && [ ! -f "${ISO}" ]; then
    echo "ошибка: ISO не найден: ${ISO}" >&2
    echo "сначала: make iso TARGET=${TARGET}" >&2
    exit 1
fi

command -v qemu-system-x86_64 >/dev/null || {
    echo "ошибка: qemu-system-x86_64 не установлен" >&2
    exit 1
}

if [ "${ACCEL[0]}" = "-accel" ] && ! { [ -r /dev/kvm ] && [ -w /dev/kvm ]; }; then
    echo "предупреждение: /dev/kvm недоступен, переключаюсь на TCG (медленно)" >&2
    ACCEL=(-accel tcg,thread=multi)
fi

mkdir -p "${RUN_DIR}"

ARGS=(
    -m "${MEM}"
    -smp 2
    -vga std
    -nic user,model=e1000
    -usb -device usb-tablet
)

if [ "${INSTALLED}" -eq 1 ]; then
    # Только диск: CD не подключаем вовсе, иначе BIOS снова выберет его.
    ARGS+=(-boot c)
else
    ARGS+=(-boot d -cdrom "${ISO}")
fi

if [ "${UEFI}" -eq 1 ]; then
    OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
    OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS_4M.fd"
    if [ ! -f "${OVMF_CODE}" ] || [ ! -f "${OVMF_VARS_TEMPLATE}" ]; then
        echo "ошибка: OVMF не найден (${OVMF_CODE}); установите пакет ovmf" >&2
        exit 1
    fi
    VARS="${RUN_DIR}/OVMF_VARS.fd"
    if [ ! -f "${VARS}" ]; then
        cp -f "${OVMF_VARS_TEMPLATE}" "${VARS}"
    fi
    ARGS+=(
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}"
        -drive "if=pflash,format=raw,unit=1,file=${VARS}"
    )
fi

if [ "${USE_DISK}" -eq 1 ]; then
    DISK="${RUN_DIR}/disk.qcow2"
    # --dry-run ничего не создаёт и не меняет на диске.
    if [ "${DRY_RUN}" -eq 0 ]; then
        if [ "${INSTALLED}" -eq 1 ] && [ ! -f "${DISK}" ]; then
            echo "ошибка: диска нет: ${DISK}" >&2
            echo "сначала установите систему: make run-install TARGET=${TARGET}" >&2
            exit 1
        fi
        if [ ! -f "${DISK}" ]; then
            echo "--> создаю диск ${DISK} (${DISK_SIZE})"
            qemu-img create -f qcow2 "${DISK}" "${DISK_SIZE}" >/dev/null
        else
            echo "--> использую существующий диск ${DISK}"
        fi
    fi
    ARGS+=(-drive "file=${DISK},if=virtio,format=qcow2,media=disk")
fi

# --- Способ показа экрана ---------------------------------------------------
# auto: самое отзывчивое из доступного. На практике SPICE (remote-viewer)
# оказался шустрее локального GTK (и даёт буфер обмена), поэтому он первый;
# GTK — запасной, VNC — для удалённой работы. Без графической сессии
# локальное окно бессмысленно, идём в VNC.
qemu_has_display() {
    qemu-system-x86_64 -display help 2>/dev/null | grep -qx "$1"
}

if [ "${VIEWER}" = "auto" ]; then
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        VIEWER="vnc"
    elif command -v remote-viewer >/dev/null 2>&1; then
        VIEWER="spice"
    elif qemu_has_display gtk; then
        VIEWER="gtk"
    else
        VIEWER="vnc"
    fi
fi

case "${VIEWER}" in
    gtk)
        if ! qemu_has_display gtk; then
            echo "предупреждение: qemu без -display gtk (нет пакета qemu-system-gui)" >&2
        fi
        ARGS+=(-display gtk)
        ;;
    spice)
        ARGS+=(-display spice-app)
        ;;
    vnc)
        # -vnc <host>:<display>; порт = 5900 + display, значит нужен display 0.
        ARGS+=(-vnc 127.0.0.1:0)
        ;;
    none)
        ARGS+=(-display none)
        ;;
    *)
        echo "ошибка: неизвестный --viewer '${VIEWER}' (auto|gtk|spice|vnc|none)" >&2
        exit 2
        ;;
esac

if [ "${INSTALLED}" -eq 1 ]; then
    echo "==> qemu: установленная система на ${RUN_DIR}/disk.qcow2 ($([ "${UEFI}" -eq 1 ] && echo UEFI || echo BIOS), ${MEM} MiB)"
else
    echo "==> qemu: ${ISO##*/} ($([ "${UEFI}" -eq 1 ] && echo UEFI || echo BIOS), ${MEM} MiB)"
    echo "    вход в live: user / live"
fi
case "${VIEWER}" in
    gtk)   echo "    экран: окно GTK" ;;
    spice) echo "    экран: окно SPICE (remote-viewer)" ;;
    none)  echo "    экран: без окна (-display none)" ;;
    vnc)   echo "    экран: VNC 127.0.0.1:5900 (krdc vnc://127.0.0.1:5900)" ;;
esac
echo "    остановить VM — Ctrl+C в этом терминале"

if [ "${DRY_RUN}" -eq 1 ]; then
    echo "    viewer: ${VIEWER}"
    echo "    команда: qemu-system-x86_64 ${ACCEL[*]} ${ARGS[*]}"
    exit 0
fi

if [ "${VIEWER}" = "vnc" ]; then
    qemu-system-x86_64 "${ACCEL[@]}" "${ARGS[@]}" &
    qemu_pid=$!
    # Ждём, пока VNC начнёт слушать порт 5900, и только затем подключаем krdc:
    # иначе krdc откроется раньше qemu и покажет «connection refused».
    _i=0
    while [ "${_i}" -lt 100 ]; do
        if (exec 3<>/dev/tcp/127.0.0.1/5900) 2>/dev/null; then
            break
        fi
        kill -0 "${qemu_pid}" 2>/dev/null || break
        sleep 0.2
        _i=$((_i + 1))
    done
    if command -v krdc >/dev/null 2>&1; then
        krdc "vnc://127.0.0.1:5900" >/dev/null 2>&1 &
    else
        echo "    krdc не найден: подключитесь вручную — krdc vnc://127.0.0.1:5900"
    fi
    wait "${qemu_pid}"
else
    exec qemu-system-x86_64 "${ACCEL[@]}" "${ARGS[@]}"
fi
