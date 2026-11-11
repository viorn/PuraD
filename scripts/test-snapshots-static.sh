#!/bin/bash
# scripts/test-snapshots-static.sh — статические проверки systemd-части
# снимков btrfs: юнит первого снимка, скрипт и drop-in grub-btrfsd.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UNIT="${REPO_DIR}/config/includes.chroot/usr/lib/systemd/system/purad-first-snapshot.service"
SCRIPT="${REPO_DIR}/config/includes.chroot/usr/lib/purad/first-snapshot"
DROPIN="${REPO_DIR}/config/includes.chroot/etc/systemd/system/grub-btrfsd.service.d/10-purad-timeshift.conf"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

echo "==> файлы"
for path in "${UNIT}" "${SCRIPT}" "${DROPIN}"; do
    [ -f "${path}" ] || fail "нет ${path}"
done
[ -x "${SCRIPT}" ] || fail "${SCRIPT} не исполняемый"

echo "==> юнит"
grep -q '^After=local-fs.target$' "${UNIT}" || fail "нет After=local-fs.target"
grep -q '^Before=grub-btrfsd.service$' "${UNIT}" || fail "нет Before=grub-btrfsd.service"
grep -q '^ConditionPathExists=/var/lib/purad/btrfs$' "${UNIT}" || fail "нет условия на маркер btrfs"
grep -q '^ConditionPathExists=!/var/lib/purad/first-snapshot.done$' "${UNIT}" || fail "нет условия на done"
grep -q '^ExecStart=/usr/lib/purad/first-snapshot$' "${UNIT}" || fail "нет ExecStart"

echo "==> скрипт"
sh -n "${SCRIPT}" || fail "синтаксис ${SCRIPT}"
grep -q 'timeshift --create --btrfs --scripted --yes' "${SCRIPT}" || fail "нет timeshift --create"
# Timeshift 24.06.6 отвергает "O" в --tags, хотя печатает его в списке
# допустимых; без --tags тег ondemand ставится по умолчанию.
if grep -q -- '--tags O' "${SCRIPT}"; then
    fail "Timeshift 24.06.6 не принимает --tags O"
fi
grep -q 'findmnt -no FSTYPE /' "${SCRIPT}" || fail "нет защиты от загрузки в снимок"
grep -q 'PuraD: initial snapshot' "${SCRIPT}" || fail "нет комментария снимка"
grep -q 'update-grub' "${SCRIPT}" || fail "нет update-grub: меню GRUB не обновится"
grep -q 'first-snapshot.done' "${SCRIPT}" || fail "нет маркера done"

echo "==> drop-in grub-btrfsd"
grep -q '^ExecStart=$' "${DROPIN}" || fail "drop-in не сбрасывает ExecStart"
grep -q '^ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto$' "${DROPIN}" || fail "нет ExecStart --timeshift-auto"

echo "PASS: systemd-часть снимков btrfs"