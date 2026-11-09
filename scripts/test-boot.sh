#!/bin/bash
# scripts/test-boot.sh — проверка загрузки ISO PuraD в qemu (BIOS и/или UEFI).
#
# Использование:
#   scripts/test-boot.sh [trixie|sid] [--bios|--uefi|--all] [--timeout N] [--mem MiB]
#
# Что делает:
#   1. Находит ISO в builds/<target>/.
#   2. Запускает qemu без графики, serial-консоль на stdio.
#   3. Ждёт login:, входит как user/live (умолчания live-config), выполняет
#      id / cat /etc/os-release / uname -r и ищет маркер PURAD_DONE.
#   4. Гасит VM и возвращает 0/1; полный лог — builds/<target>/test-logs/.
#
# Требования: qemu-system-x86_64; для UEFI — OVMF (ovmf). KVM не обязателен:
# при недоступном /dev/kvm используется TCG (медленнее).

set -euo pipefail

TARGET="trixie"
MODE="all"
TIMEOUT=180
MEM=2048

while [ $# -gt 0 ]; do
    case "$1" in
        trixie|sid)
            TARGET="$1"
            ;;
        --bios)
            MODE="bios"
            ;;
        --uefi)
            MODE="uefi"
            ;;
        --all)
            MODE="all"
            ;;
        --timeout)
            TIMEOUT="${2:?--timeout требует значение}"
            shift
            ;;
        --mem)
            MEM="${2:?--mem требует значение}"
            shift
            ;;
        -h|--help)
            sed -n '2,20p' "$0"
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
LOG_DIR="${REPO_DIR}/builds/${TARGET}/test-logs"

if [ ! -f "${ISO}" ]; then
    echo "ошибка: ISO не найден: ${ISO}" >&2
    echo "сначала: make iso TARGET=${TARGET}" >&2
    exit 1
fi

command -v qemu-system-x86_64 >/dev/null || {
    echo "ошибка: qemu-system-x86_64 не установлен" >&2
    exit 1
}

OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS_4M.fd"

mkdir -p "${LOG_DIR}"

# KVM доступен только если у пользователя есть права на /dev/kvm.
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=(-accel kvm)
    ACCEL_NAME="kvm"
else
    ACCEL=(-accel tcg,thread=multi)
    ACCEL_NAME="tcg"
fi

COMMON_ARGS=(
    -m "${MEM}"
    -smp 2
    -display none
    -monitor none
    -no-reboot
    "${ACCEL[@]}"
)

# run_case <имя> <qemu-аргументы...>
# Возвращает 0, если live-сессия дошла до shell и выполнила маркер.
run_case() {
    local name="$1"
    shift
    local log="${LOG_DIR}/${TARGET}-${name}.log"
    local stage=0 line
    local deadline=$((SECONDS + TIMEOUT))
    local ok=0

    echo "==> ${name} (${ACCEL_NAME}), лог: ${log}"
    : > "${log}"

    coproc VM { qemu-system-x86_64 "${COMMON_ARGS[@]}" "$@" -serial stdio 2>&1; }
    local vm_pid="${VM_PID}"
    local out="${VM[0]}"
    local in="${VM[1]}"

    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if ! IFS= read -r -t 2 line <&"${out}"; then
            kill -0 "${vm_pid}" 2>/dev/null || break
            continue
        fi

        line="${line%$'\r'}"
        printf '%s\n' "${line}" >> "${log}"

        case "${stage}" in
            0)
                # agetty печатает "debian login: " без перевода строки, поэтому
                # ждём баннер getty ("Debian GNU/Linux 13 debian ttyS0") — он
                # заканчивается \n и гарантирует, что логин уже готов.
                if [[ "${line}" == *"Debian GNU/Linux"*"ttyS0"* ]]; then
                    sleep 1
                    printf 'user\n' >&"${in}"
                    sleep 2
                    printf 'live\n' >&"${in}"
                    # Приглашение shell ("user@debian:~$ ") печатается без \n,
                    # поэтому команды отправляем по таймеру, а не по подстроке.
                    sleep 4
                    printf 'echo PURAD_MARK; id; cat /etc/os-release; uname -r; echo PURAD_DONE\n' >&"${in}"
                    stage=3
                fi
                ;;
            3)
                # Только вывод команды (строка ровно PURAD_DONE), а не её эхо.
                if [[ "${line}" == "PURAD_DONE" ]]; then
                    ok=1
                    printf 'sudo -n poweroff -f\n' >&"${in}" || true
                    stage=4
                    sleep 5
                    break
                fi
                ;;
        esac
    done

    kill "${vm_pid}" 2>/dev/null || true
    wait "${vm_pid}" 2>/dev/null || true

    if [ "${ok}" -eq 1 ] && grep -q '^PURAD_DONE$' "${log}"; then
        echo "    OK: live-сессия загрузилась, вход user/live и команды выполнены"
        grep -E '^(uid=|PRETTY_NAME=|Linux )' "${log}" | sed 's/^/    /' || true
        return 0
    fi

    echo "    FAIL: за ${TIMEOUT}s не дошли до shell (см. ${log})" >&2
    tail -20 "${log}" | sed 's/^/    | /' >&2 || true
    return 1
}

run_bios() {
    run_case bios -boot d -cdrom "${ISO}"
}

run_uefi() {
    if [ ! -f "${OVMF_CODE}" ] || [ ! -f "${OVMF_VARS_TEMPLATE}" ]; then
        echo "ошибка: OVMF не найден (${OVMF_CODE}); установите пакет ovmf" >&2
        return 1
    fi
    local vars="${LOG_DIR}/OVMF_VARS-${TARGET}.fd"
    cp -f "${OVMF_VARS_TEMPLATE}" "${vars}"
    run_case uefi \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,unit=1,file=${vars}" \
        -cdrom "${ISO}"
}

rc=0
case "${MODE}" in
    bios)
        run_bios || rc=1
        ;;
    uefi)
        run_uefi || rc=1
        ;;
    all)
        run_bios || rc=1
        run_uefi || rc=1
        ;;
esac

if [ "${rc}" -eq 0 ]; then
    echo "==> все проверки прошли"
else
    echo "==> есть неудачные проверки" >&2
fi
exit "${rc}"
