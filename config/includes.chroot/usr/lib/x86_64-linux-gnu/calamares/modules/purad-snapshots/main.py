#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 PuraD
# SPDX-License-Identifier: GPL-3.0-or-later
"""Снимки btrfs: Timeshift + grub-btrfs в установленной системе.

Модуль выполняется после `packages`, до `initramfscfg`/`initramfs`.
Порядок важен: пакет grub-btrfs приносит initramfs-tools-хук overlayfs,
и штатный шаг `initramfs` должен успеть перегенерировать initramfs
установленной системы с этим хуком.

На ext4 модуль ничего не делает. На btrfs:

1. ставит `timeshift`, `grub-btrfs` и `pkexec` из локального репозитория
   на носителе (без сети);
2. пишет `/etc/timeshift/timeshift.json` в btrfs-режиме без расписания;
3. создаёт маркер `/var/lib/purad/btrfs`;
4. включает `purad-first-snapshot.service` и `grub-btrfsd.service`.

Начальный снимок создаётся не здесь: Timeshift в live-режиме отказывается
работать, поэтому это делает `purad-first-snapshot` при первом запуске
установленной системы.
"""

import json
import os

import libcalamares


MEDIA_LIST = "/etc/apt/sources.list.d/debian-live-media.list"
TIMESHIFT_DIR = "etc/timeshift"
TIMESHIFT_DEFAULT = os.path.join(TIMESHIFT_DIR, "default.json")
TIMESHIFT_CONFIG = os.path.join(TIMESHIFT_DIR, "timeshift.json")
MARKER = "var/lib/purad/btrfs"

# Значения Timeshift хранит строками (см. /etc/timeshift/default.json).
TIMESHIFT_SETTINGS = {
    "backup_device_uuid": "",
    "parent_device_uuid": "",
    "do_first_run": "false",
    "btrfs_mode": "true",
    "include_btrfs_home": "false",
    "schedule_monthly": "false",
    "schedule_weekly": "false",
    "schedule_daily": "false",
    "schedule_hourly": "false",
    "schedule_boot": "false",
}


def pretty_name():
    return "Снимки btrfs (Timeshift + grub-btrfs)"


def target_root_fs(root, partitions):
    """ФС целевого корня: из global storage или из /etc/fstab.

    `partitions` — список разделов Calamares; у корня mountPoint == "/".
    Фолбэк нужен, если модуль запускают в нестандартной последовательности
    или global storage пуст.
    """
    for part in partitions or []:
        if part.get("mountPoint") == "/":
            return (part.get("fs") or "").lower()

    try:
        with open(os.path.join(root, "etc/fstab")) as fstab:
            for line in fstab:
                fields = line.split()
                if len(fields) < 4:
                    continue
                if fields[1] == "/" and fields[2] == "btrfs":
                    options = fields[3]
                    if "subvol=/@" in options or "subvol=@" in options:
                        return "btrfs"
    except OSError:
        pass

    return ""


def apt_get(root, args):
    """apt-get в целевом chroot, по возможности только с носителя.

    На время установки `sources-media` пишет единственный нужный источник —
    `file:/run/live/medium`. Сетевые `sources.list` могут быть недоступны,
    поэтому явно ограничиваем apt этим файлом: установка не должна зависеть
    от сети.
    """
    command = ["/usr/bin/env", "DEBIAN_FRONTEND=noninteractive", "apt-get"]
    if os.path.exists(os.path.join(root, MEDIA_LIST.lstrip("/"))):
        command += [
            "-o", "Dir::Etc::sourcelist={}".format(MEDIA_LIST),
            "-o", "Dir::Etc::sourceparts=-",
        ]
    command += args
    return libcalamares.utils.target_env_call(command)


def install_packages(root):
    rc = apt_get(root, ["update"])
    if rc != 0:
        raise RuntimeError("apt-get update завершился с кодом {}".format(rc))

    rc = apt_get(
        root,
        [
            "install",
            "-y",
            "--no-install-recommends",
            "timeshift",
            "grub-btrfs",
            "pkexec",
        ],
    )
    if rc != 0:
        raise RuntimeError("apt-get install завершился с кодом {}".format(rc))


def write_timeshift_config(root):
    """Настроить Timeshift на btrfs без расписания и без @home."""
    default_path = os.path.join(root, TIMESHIFT_DEFAULT)
    with open(default_path) as config_file:
        config = json.load(config_file)

    config.update(TIMESHIFT_SETTINGS)

    path = os.path.join(root, TIMESHIFT_CONFIG)
    with open(path, "w") as config_file:
        json.dump(config, config_file, indent=2, sort_keys=True)
        config_file.write("\n")
    os.chmod(path, 0o644)


def mark_btrfs(root):
    path = os.path.join(root, MARKER)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").close()

    libcalamares.utils.debug("PuraD: маркер btrfs создан: {}".format(path))


def enable_units(root):
    for unit in ("purad-first-snapshot.service", "grub-btrfsd.service"):
        unit_path = os.path.join(root, "usr/lib/systemd/system", unit)
        if not os.path.exists(unit_path):
            libcalamares.utils.warning(
                "PuraD: нет юнита {}, пропускаю включение".format(unit))
            continue
        rc = libcalamares.utils.target_env_call(["systemctl", "enable", unit])
        if rc != 0:
            libcalamares.utils.warning(
                "PuraD: systemctl enable {} вернул {}".format(unit, rc))


def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        libcalamares.utils.warning("PuraD: нет rootMountPoint, пропускаю снимки")
        return None

    partitions = libcalamares.globalstorage.value("partitions") or []
    filesystem = target_root_fs(root, partitions)
    if filesystem != "btrfs":
        libcalamares.utils.debug(
            "PuraD: корень {} — не btrfs, снимки не настраиваю".format(
                filesystem or "неизвестен"))
        return None

    try:
        install_packages(root)
        write_timeshift_config(root)
        mark_btrfs(root)
        enable_units(root)
    except Exception as error:
        # Снимки — дополнительная функция: их сбой не должен валить установку.
        libcalamares.utils.warning(
            "PuraD: не удалось настроить снимки btrfs: {}".format(error))
        return None

    libcalamares.utils.debug("PuraD: снимки btrfs настроены")
    return None