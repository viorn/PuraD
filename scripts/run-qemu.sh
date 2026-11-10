#!/bin/bash
# scripts/run-qemu.sh — интерактивный запуск собранного ISO в qemu (с окном).
#
# Использование:
#   scripts/run-qemu.sh [trixie|sid] [--uefi] [--disk [SIZE]] [--installed]
#                       [--mem MiB] [--tcg]
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
        -h|--help)
            sed -n '2,22p' "$0"
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

if [ "${INSTALLED}" -eq 0 ] && [ ! -f "${ISO}" ]; then
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
    ARGS+=(-drive "file=${DISK},if=virtio,format=qcow2,media=disk")
fi

if [ "${INSTALLED}" -eq 1 ]; then
    echo "==> qemu: установленная система на ${RUN_DIR}/disk.qcow2 ($([ "${UEFI}" -eq 1 ] && echo UEFI || echo BIOS), ${MEM} MiB)"
else
    echo "==> qemu: ${ISO##*/} ($([ "${UEFI}" -eq 1 ] && echo UEFI || echo BIOS), ${MEM} MiB)"
    echo "    вход в live: user / live"
fi
echo "    выход из VM — Ctrl+Alt+G, затем закрыть окно"

exec qemu-system-x86_64 "${ACCEL[@]}" "${ARGS[@]}" "${@}"
