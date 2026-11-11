#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 PuraD
# SPDX-License-Identifier: GPL-3.0-or-later
"""Проверка Calamares-модуля purad-snapshots без запуска Calamares.

Модуль импортирует libcalamares, которого на хосте нет. Подставляем
минимальную заглушку и импортируем main.py по пути. Проверяем чистые
функции, которые принимают решения о файловой системе и конфиге.
"""
import importlib.util
import json
import os
import sys
import tempfile
import types

sys.dont_write_bytecode = True

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULE_PATH = os.path.join(
    REPO,
    "config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/"
    "purad-snapshots/main.py",
)


def stub_libcalamares():
    lib = types.ModuleType("libcalamares")

    class GlobalStorage:
        def __init__(self):
            self.values = {}

        def value(self, key):
            return self.values.get(key)

        def insert(self, key, value):
            self.values[key] = value

    def noop(*args, **kwargs):
        return None

    lib.globalstorage = GlobalStorage()
    lib.job = types.SimpleNamespace(configuration={})
    lib.utils = types.SimpleNamespace(
        debug=noop,
        warning=noop,
        error=noop,
        target_env_call=lambda *a, **k: 0,
    )
    return lib


def load_module():
    sys.modules["libcalamares"] = stub_libcalamares()
    spec = importlib.util.spec_from_file_location("purad_snapshots", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL: не удалось загрузить {}".format(MODULE_PATH))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check(name, condition):
    if not condition:
        raise SystemExit("FAIL: {}".format(name))
    print("ok: {}".format(name))


def main():
    module = load_module()

    check(
        "btrfs partition",
        module.target_root_fs("/nonexistent", [{"mountPoint": "/", "fs": "btrfs"}])
        == "btrfs",
    )
    check(
        "ext4 partition",
        module.target_root_fs("/nonexistent", [{"mountPoint": "/", "fs": "ext4"}])
        == "ext4",
    )

    with tempfile.TemporaryDirectory() as root:
        os.makedirs(os.path.join(root, "etc"))
        with open(os.path.join(root, "etc/fstab"), "w") as fstab:
            fstab.write("UUID=1 / btrfs defaults,subvol=/@ 0 0\n")
        check("fstab fallback", module.target_root_fs(root, []) == "btrfs")

    with tempfile.TemporaryDirectory() as root:
        timeshift_dir = os.path.join(root, "etc/timeshift")
        os.makedirs(timeshift_dir)
        with open(os.path.join(timeshift_dir, "default.json"), "w") as f:
            json.dump(
                {
                    "backup_device_uuid": "old-device",
                    "parent_device_uuid": "old-parent",
                    "do_first_run": "true",
                    "btrfs_mode": "false",
                    "include_btrfs_home": "true",
                    "schedule_monthly": "true",
                    "schedule_weekly": "true",
                    "schedule_daily": "true",
                    "schedule_hourly": "true",
                    "schedule_boot": "true",
                },
                f,
            )

        module.write_timeshift_config(root)

        with open(os.path.join(timeshift_dir, "timeshift.json")) as f:
            cfg = json.load(f)

        check("backup_device_uuid", cfg["backup_device_uuid"] == "")
        check("do_first_run", cfg["do_first_run"] == "false")
        check("btrfs_mode", cfg["btrfs_mode"] == "true")
        check("include_btrfs_home", cfg["include_btrfs_home"] == "false")
        for key in (
            "schedule_monthly",
            "schedule_weekly",
            "schedule_daily",
            "schedule_hourly",
            "schedule_boot",
        ):
            check(key, cfg[key] == "false")

    print("PASS: purad-snapshots")


if __name__ == "__main__":
    main()