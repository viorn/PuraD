#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 PuraD
# SPDX-License-Identifier: GPL-3.0-or-later
"""Доделать резервный путь загрузки UEFI (\\EFI\\BOOT\\BOOTX64.EFI).

Calamares с `installEFIFallback: true` копирует в `EFI/boot` только сам
загрузчик (`grubx64.efi` → `bootx64.efi`) и не кладёт туда `grub.cfg`.
Прошивка, которая потеряла запись в NVRAM (сброс настроек, перенос диска
в другую машину, «кривой» efibootmgr), уходит на съёмный путь
`\\EFI\\BOOT\\BOOTX64.EFI`, GRUB поднимается без конфига и остаётся в
приглашении `grub>`.

Модуль доводит `EFI/boot` до состояния, которое оставляет после себя
`grub-install --removable` на Debian: shim + MOK-менеджер + grub + конфиг
из каталога, куда Calamares положил загрузчик (`EFI/PuraD`).
"""

import os
import shutil

import libcalamares


EFI_FALLBACK_DIR = ("EFI", "boot")
# Набор файлов съёмного пути. Shim ищет grubx64.efi рядом с собой, поэтому
# в EFI/boot нужны оба (и mmx64.efi — MOK-менеджер для Secure Boot).
FALLBACK_CHAIN = ("mmx64.efi", "grubx64.efi", "grub.cfg")


def pretty_name():
    return "Настройка резервного пути загрузки UEFI"


def find_bootloader_dir(efi_dir):
    """Каталог на ESP, куда Calamares положил загрузчик (EFI/PuraD).

    Ищем по grubx64.efi: EFI/boot намеренно пропускаем — это и есть
    съёмный путь, который мы наполняем.
    """
    skip = EFI_FALLBACK_DIR[1].lower()
    try:
        entries = sorted(os.listdir(efi_dir))
    except OSError:
        return None
    for name in entries:
        path = os.path.join(efi_dir, name)
        if not os.path.isdir(path) or name.lower() == skip:
            continue
        if os.path.exists(os.path.join(path, "grubx64.efi")):
            return path
    return None


def copy_missing(src, dst):
    if not os.path.exists(src):
        return False
    if os.path.exists(dst):
        return False
    shutil.copyfile(src, dst)
    return True


def run():
    if libcalamares.globalstorage.value("firmwareType") != "efi":
        return None

    root = libcalamares.globalstorage.value("rootMountPoint")
    esp_rel = libcalamares.globalstorage.value("efiSystemPartition")
    if not root or not esp_rel:
        libcalamares.utils.warning("нет rootMountPoint/efiSystemPartition, пропускаю")
        return None

    efi_dir = os.path.join(root, esp_rel.lstrip("/"), "EFI")
    bootloader_dir = find_bootloader_dir(efi_dir)
    if bootloader_dir is None:
        libcalamares.utils.warning("не нашёл каталог загрузчика в {}, пропускаю".format(efi_dir))
        return None

    fallback_dir = os.path.join(root, esp_rel.lstrip("/"), *EFI_FALLBACK_DIR)
    os.makedirs(fallback_dir, exist_ok=True)

    copied = []
    for name in FALLBACK_CHAIN:
        if copy_missing(os.path.join(bootloader_dir, name), os.path.join(fallback_dir, name)):
            copied.append(name)

    # Первым этапом съёмного пути ставим shim (как grub-install --removable
    # в Debian); без него — сам GRUB.
    first_stage = os.path.join(fallback_dir, "bootx64.efi")
    shim = os.path.join(bootloader_dir, "shimx64.efi")
    source = shim if os.path.exists(shim) else os.path.join(bootloader_dir, "grubx64.efi")
    if not os.path.exists(first_stage) or os.path.getsize(first_stage) != os.path.getsize(source):
        shutil.copyfile(source, first_stage)
        copied.append("bootx64.efi")

    libcalamares.utils.debug(
        "UEFI fallback: {} → {}, добавлено: {}".format(
            bootloader_dir, fallback_dir, ", ".join(copied) or "ничего"))
    return None
