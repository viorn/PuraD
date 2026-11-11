#!/bin/bash
# scripts/test-boot.sh — проверка загрузки ISO PuraD в qemu (BIOS и/или UEFI).
#
# Использование:
#   scripts/test-boot.sh [trixie|sid] [--bios|--uefi|--all] [--timeout N]
#                        [--mem MiB] [--desktop] [--installer]
#
# Что делает:
#   1. Находит ISO в builds/<target>/.
#   2. Запускает qemu без графики, serial-консоль на stdio.
#   3. Ждёт баннер getty, входит как user/live (умолчания live-config),
#      выполняет id / cat /etc/os-release / uname -r и ждёт последнюю строку вывода.
#   4. С --desktop дополнительно ждёт графическую сессию и требует Type=x11
#      (Этап 4: live-сессия жёстко на X11).
#   5. С --installer (включает --desktop) дополнительно проверяет установщик:
#      pkexec без пароля (правило polkit live-сессии) и что Calamares
#      запускается из live-сессии и живёт дольше 30 c, то есть дошёл до UI
#      (Этап 6).
#   6. Гасит VM и возвращает 0/1; полный лог — builds/<target>/test-logs/.
#
# Требования: qemu-system-x86_64; для UEFI — OVMF (ovmf). KVM не обязателен:
# при недоступном /dev/kvm используется TCG (медленнее).

set -euo pipefail

TARGET="trixie"
MODE="all"
TIMEOUT=180
MEM=2048
DESKTOP=0
INSTALLER=0

while [ $# -gt 0 ]; do
    case "$1" in
        trixie|sid)
            TARGET="$1"
            ;;
        --desktop)
            DESKTOP=1
            ;;
        --installer)
            DESKTOP=1
            INSTALLER=1
            TIMEOUT=360
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

# Проверка установщика до загрузки: шаг bootloader в Calamares ставит grub из
# локального репозитория на носителе (config/hooks/normal/*.binary). Если его
# нет, тест всё равно пройдёт пол-пути и упадёт через 10 минут с
# "Package 'grub-efi' has no installation candidate". Лучше сказать сразу.
if [ "${INSTALLER}" -eq 1 ]; then
    REPO_DIR_IDX="${REPO_DIR}/builds/${TARGET}/binary/dists/${TARGET}/main/binary-amd64/Packages"
    if [ -d "${REPO_DIR}/builds/${TARGET}/binary" ] && [ ! -f "${REPO_DIR_IDX}" ]; then
        echo "предупреждение: на носителе нет локального apt-репозитория для установщика" >&2
        echo "  ожидался ${REPO_DIR_IDX}" >&2
        echo "  установка загрузчика (grub-efi/grub-pc) потребует сети" >&2
    fi

    # Снимки btrfs: модуль purad-snapshots ставит эти пакеты из локального
    # репозитория на носителе. Если их там нет, установка на btrfs пройдёт,
    # но без Timeshift/grub-btrfs (модуль предупредит и продолжит).
    if [ -f "${REPO_DIR_IDX}" ]; then
        for pkg in timeshift grub-btrfs inotify-tools; do
            grep -q "^Package: ${pkg}$" "${REPO_DIR_IDX}" || \
                echo "предупреждение: в локальном репозитории нет ${pkg}" >&2
        done
    fi

    # Шаг packages удаляет из установленной системы live-* пакеты. Если такого
    # пакета в образе нет, apt-get remove завершается с кодом 100 и установка
    # обрывается («Ошибка менеджера пакетов» — так падало на live-task-*).
    PACKAGES_CONF="${REPO_DIR}/config/includes.chroot/etc/calamares/modules/packages.conf"
    LIVE_PACKAGES="${REPO_DIR}/builds/${TARGET}/chroot.packages.live"
    if [ -f "${PACKAGES_CONF}" ] && [ -f "${LIVE_PACKAGES}" ]; then
        missing=""
        while IFS= read -r pkg; do
            [ -n "${pkg}" ] || continue
            grep -qE "^${pkg}[[:space:]]" "${LIVE_PACKAGES}" || missing="${missing} ${pkg}"
        done < <(sed -n 's/^ *- \([a-z0-9][a-z0-9.+_-]*\)$/\1/p' "${PACKAGES_CONF}")
        if [ -n "${missing}" ]; then
            echo "ошибка: установщик удаляет пакеты, которых нет в образе:${missing}" >&2
            echo "  apt-get remove вернёт 100, установка упадёт на шаге packages" >&2
            exit 1
        fi
    fi
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

# С --installer подкладываем пустой virtio-диск: без него Calamares не проходит
# собственные требования (storage/partitions) и не пускает дальше welcome.
INSTALL_DISK="${LOG_DIR}/install-${TARGET}.qcow2"
if [ "${INSTALLER}" -eq 1 ]; then
    # 24G: welcome.conf требует 15 GB свободного места, а qcow2 разряжённый.
    command -v qemu-img >/dev/null && { [ -f "${INSTALL_DISK}" ] || qemu-img create -f qcow2 "${INSTALL_DISK}" 24G >/dev/null; }
    [ -f "${INSTALL_DISK}" ] && COMMON_ARGS+=(-drive "file=${INSTALL_DISK},if=virtio,format=qcow2,media=disk")
fi

# run_case <имя> <qemu-аргументы...>
# Возвращает 0, если live-сессия дошла до shell и выполнила маркер.
run_case() {
    local name="$1"
    shift
    local log="${LOG_DIR}/${TARGET}-${name}.log"
    local stage=0 line
    local deadline=$((SECONDS + TIMEOUT))
    local ok=0
    local guest_cmd

    if [ "${DESKTOP}" -eq 1 ]; then
        # Ждём сессию Type=x11 (после автологина SDDM), затем печатаем её
        # параметры и списки доступных сессий.
        guest_cmd='i=0; G=; while [ -z "$G" ] && [ $i -lt 60 ]; do for s in $(loginctl list-sessions --no-legend | awk "{print \$1}"); do t=$(loginctl show-session "$s" -p Type --value 2>/dev/null); [ "$t" = x11 ] && G=$s; done; [ -n "$G" ] || sleep 2; i=$((i+1)); done; echo XSESSION=$G; loginctl show-session "$G" -p Type -p Desktop -p Active; echo WAYLAND_SESSIONS:; ls /usr/share/wayland-sessions; echo XSESSIONS:; ls /usr/share/xsessions'
    else
        guest_cmd='echo PURAD_MARK; id; cat /etc/os-release; uname -r'
    fi

    # Вторая порция команд (--installer) отправляется не сразу, а когда
    # отработает первая: если отправить всё одной пачкой, bash в момент выхода
    # из цикла ожидания сессии теряет первый символ следующей строки
    # ("export" -> "xport", видели в логе).
    guest_cmd2=""

    if [ "${INSTALLER}" -eq 1 ]; then
        # Проверка установщика (Этап 6).
        # 1) XAUTHORITY берём из окружения процессов Plasma: в X11-сессии SDDM
        #    X-авторизация лежит в /var/run/sddm/xauth_*, без переменной
        #    Calamares не подключится к :0.
        # 2) pkexec без пароля — проверка правила polkit из live-config
        #    (0087-purad-calamares).
        # 3) Запускаем установщик на 30 c: если UI не поднялся, Calamares
        #    завершается сам (нет дисплея/QML), поэтому «жив через 30 c» и есть
        #    признак дошедшего до экрана приветствия окна.
        guest_cmd2='export DISPLAY=:0
# X-авторизация. Xorg под SDDM запущен с -auth /run/sddm/xauth_XXXX, а сам
# каталог /run/sddm доступен только root, поэтому пользователь видит пустоту и
# Calamares падает с "Authorization required, but no authorization protocol
# specified". Берём cookie через passwordless sudo и кладём копию в /tmp:
# pkexec сохраняет DISPLAY и XAUTHORITY, этого достаточно.
for f in $(sudo -n sh -c "ls /run/sddm/xauth_* /var/run/sddm/xauth_* 2>/dev/null"); do
    if sudo -n cp "$f" /tmp/purad-xauth 2>/dev/null; then
        sudo -n chmod 644 /tmp/purad-xauth
        export XAUTHORITY=/tmp/purad-xauth
        break
    fi
done
if [ -z "$XAUTHORITY" ]; then
    for f in /run/user/1000/xauth_* "$HOME/.Xauthority"; do
        [ -r "$f" ] && export XAUTHORITY=$f && break
    done
fi
if [ -z "$XAUTHORITY" ]; then
    # pgrep -x (по comm), а не -f: наша же команда содержит строку "plasmashell"
    # в командной строке bash -c, и -f находил её вместо процесса Plasma.
    for p in $(pgrep -x plasmashell) $(pgrep -x startplasma-x11) $(pgrep -x ksmserver); do
        xa=$(tr "\\0" "\\n" < /proc/$p/environ 2>/dev/null | sed -n "s/^XAUTHORITY=//p")
        [ -n "$xa" ] && export XAUTHORITY=$xa && break
    done
fi
echo DISPLAY_IS=$DISPLAY XAUTHORITY_IS=$XAUTHORITY
# Plasma поднимается не мгновенно после регистрации x11-сессии, ждём до 60 c.
i=0; while ! pgrep -x plasmashell >/dev/null && [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done
echo PLASMASHELL=$(pgrep -x -c plasmashell)
if [ "$(pgrep -x -c plasmashell)" = "0" ]; then
    echo PLASMA_DIAG_BEGIN
    sudo -n journalctl -b --no-pager 2>&1 | grep -iE "plasmashell|kwin_|ksmserver|startplasma|plasma_session|org.kde" | tail -20
    sudo -n journalctl -b -u sddm --no-pager 2>&1 | tail -10
    echo SDDM_CONF:; sudo -n sh -c "grep -r . /etc/sddm.conf /etc/sddm.conf.d/ 2>/dev/null" | head -20
    echo SESSIONS:; loginctl list-sessions --no-legend
    sudo -n journalctl -b -u sddm --no-pager 2>&1 | grep -i autologin | tail -5
    ls -la /home/user/.xsession-errors 2>&1 | head -3
    echo PLASMA_DIAG_END
fi
echo MEDIA_REPO_PACKAGES=$(ls /run/live/medium/pool/main/*.deb 2>/dev/null | wc -l)
echo MEDIA_REPO_GRUB_EFI=$(grep -c "^Package: grub-efi-amd64$" /run/live/medium/dists/trixie/main/binary-amd64/Packages 2>/dev/null || echo 0)
echo POLKIT_RULE_FILE:
sudo -n cat /etc/polkit-1/rules.d/49-purad-live-calamares.rules 2>&1
pkexec /bin/true; echo PKEXEC=$?
pkexec /usr/bin/calamares --version > /tmp/cal-version.log 2>&1; echo PKEXEC_CALAMARES_RC=$?
head -3 /tmp/cal-version.log
setsid pkexec /bin/true 2>&1; echo PKEXEC_SETSID=$?
sudo -n journalctl -b -u polkit.service --no-pager 2>&1 | tail -12
setsid /usr/bin/purad-installer -d > /tmp/calamares.log 2>&1 &
sleep 30
echo CALAMARES_PIDS=$(pgrep -x -c calamares)
echo CALAMARES_LOG_BEGIN
tail -25 /tmp/calamares.log
echo CALAMARES_LOG_END
sudo -n pkill -f /usr/bin/calamares'
    fi

    # Отдельного маркера-«эха» нет: на последовательной консоли bash иногда
    # съедает первый символ строки (видели "cho PURAD_DONE"), поэтому о
    # завершении судим по последней содержательной строке вывода — см. case ниже.

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

        # Приглашение и вывод идут через pty, поэтому в строках бывают \r не
        # только в конце (видели "\rXSESSION=1"). Убираем их полностью.
        line="${line//$'\r'/}"
        # Серийная консоль — это tty, поэтому systemd-утилиты (loginctl) и bash
        # (bracketed paste, управляющие последовательности readline) сыплют
        # ANSI-кодами: "Type=x11\x1b[m". Без чистки не совпадает ни одно
        # сравнение ниже. Чистим и то, что пишем в лог.
        line="$(printf '%s' "${line}" | LC_ALL=C sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b[()][A-Za-z0-9]//g')"
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
                    printf '%s\n' "${guest_cmd}" >&"${in}"
                    stage=3
                fi
                ;;
            3)
                # Первая порция отработала. В режиме --desktop её последняя
                # строка — список xsessions ("plasmax11.desktop"), в базовом —
                # вывод uname ("Linux debian ...").
                if [[ "${line}" == "plasmax11.desktop" && -n "${guest_cmd2}" ]]; then
                    sleep 1
                    # Многострочную порцию команд отправляем одной строкой через
                    # base64: при построчной передаче pty/readline путает ввод
                    # (видели и "xport" вместо "export", и вставку строк в
                    # вывод предыдущей команды). Ведущий пробел — на случай,
                    # если съестся первый символ.
                    local b64
                    b64="$(printf '%s' "${guest_cmd2}" | base64 -w0)"
                    printf ' bash -c "$(echo %s | base64 -d)"\n' "${b64}" >&"${in}"
                    stage=5
                    continue
                fi

                if [[ "${line}" == "plasmax11.desktop" && -z "${guest_cmd2}" ]] \
                   || [[ "${line}" == "Linux debian "* && "${DESKTOP}" -eq 0 ]]; then
                    ok=1
                    printf 'sudo -n poweroff -f\n' >&"${in}" || true
                    stage=4
                    sleep 5
                    break
                fi
                ;;
            5)
                # Последняя строка проверки установщика.
                if [[ "${line}" == "CALAMARES_LOG_END" ]]; then
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

    if [ "${ok}" -eq 1 ]; then
        if [ "${DESKTOP}" -eq 1 ] && ! { grep -q '^Type=x11$' "${log}" && grep -q '^XSESSION=[0-9]' "${log}"; }; then
            echo "    FAIL: графическая сессия не X11 (см. ${log})" >&2
            grep -E '^(XSESSION=|Type=|Desktop=|Active=|WAYLAND_SESSIONS:|XSESSIONS:|plasma)' "${log}" \
                | sed 's/^/    | /' >&2 || true
            return 1
        fi
        if [ "${INSTALLER}" -eq 1 ]; then
            local fail=0
            if ! grep -q '^PKEXEC=0$' "${log}"; then
                echo "    FAIL: pkexec без пароля не работает — нет правила polkit" >&2
                grep -E '^(PKEXEC=|DISPLAY_IS=)' "${log}" | sed 's/^/    | /' >&2 || true
                fail=1
            fi
            if ! grep -qE '^CALAMARES_PIDS=[1-9][0-9]*$' "${log}"; then
                echo "    FAIL: Calamares не запустился из live-сессии" >&2
                fail=1
            fi
            # Смотрим только на лог самого Calamares: текст правила polkit
            # (он печатается выше) сам содержит слова "Not authorized", и
            # поиск по всему логу давал ложное срабатывание.
            if sed -n '/^CALAMARES_LOG_BEGIN$/,/^CALAMARES_LOG_END$/p' "${log}" |
                grep -qE 'Not authorized|could not connect to display|Authorization required'; then
                echo "    FAIL: pkexec/X11 не пустил Calamares (Not authorized / нет дисплея)" >&2
                fail=1
            fi
            # Загрузчик установщик ставит apt'ом из локального репозитория на
            # носителе; без него установка падает на "grub-efi has no
            # installation candidate" (см. config/hooks/normal/*.binary).
            if ! grep -qE '^MEDIA_REPO_PACKAGES=[1-9][0-9]*$' "${log}"; then
                echo "    FAIL: на носителе нет локального apt-репозитория для установщика" >&2
                grep -E '^MEDIA_REPO_' "${log}" | sed 's/^/    | /' >&2 || true
                fail=1
            elif ! grep -qE '^MEDIA_REPO_GRUB_EFI=[1-9]' "${log}"; then
                echo "    FAIL: в локальном репозитории нет grub-efi" >&2
                fail=1
            fi
            sed -n '/^CALAMARES_LOG_BEGIN$/,/^CALAMARES_LOG_END$/p' "${log}" | sed 's/^/    | /' | head -30
            [ "${fail}" -eq 0 ] || return 1
            echo "    OK: установщик запускается без пароля и держит окно"
        fi
        echo "    OK: live-сессия загрузилась, вход user/live и команды выполнены"
        grep -E '^(uid=|PRETTY_NAME=|Linux debian |XSESSION=|Type=|Desktop=)' "${log}" | sed 's/^/    /' || true
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
