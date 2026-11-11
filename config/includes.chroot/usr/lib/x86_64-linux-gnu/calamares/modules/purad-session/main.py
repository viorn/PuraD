#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 PuraD
# SPDX-License-Identifier: GPL-3.0-or-later
"""Предвыбор сеанса Plasma (Wayland/X11) в установленной системе.

Ответ со страницы `packagechooser@session` лежит в global storage как
`packagechooser_session` = "wayland" | "x11".

Ключа «сессия по умолчанию» в /etc/sddm.conf нет. SDDM 0.21 берёт
предвыбранную сессию из `[Last] Session=` в /var/lib/sddm/state.conf
(sddm-state.conf(5): «This session will be preselected when the login
screen shows up»), а после удачного входа обновляет это значение сам
(`RememberLastSession`, по умолчанию true). Поэтому мы не «фиксируем»
сеанс, а задаём стартовый выбор: пользователь может переключить сессию на
экране входа, и это запомнится.

Формат значения — **полный путь** к .desktop-файлу сеанса
(`/usr/share/xsessions/plasmax11.desktop`), а не его имя: greeter сравнивает
`[Last] Session=` с `Session::fileName()`, а в sddm 0.21 в Debian там лежит
путь (проверено отладочным выводом `sessionModel.lastIndex` в теме
debian-breeze: с `plasmax11.desktop` предвыбор не срабатывал, с полным
путём — сработал). Абсолютный путь ищется в **целевой** системе: если файла
сеанса там нет, шаг молча пропускается.
"""

import os

import libcalamares


# id пункта в packagechooser-session.conf → (каталог сеансов, файл).
SESSION_FILES = {
    "wayland": ("usr/share/wayland-sessions", "plasma.desktop"),
    "x11": ("usr/share/xsessions", "plasmax11.desktop"),
}
GS_KEY = "packagechooser_session"
STATE_REL = "var/lib/sddm/state.conf"


def pretty_name():
    return "Сеанс Plasma по умолчанию"


def target_uid_gid(root, name):
    """uid и gid из /etc/passwd и /etc/group целевой системы.

    В целевую систему ставится свой пакет sddm, и его uid не обязан
    совпадать с live-системой — брать числа из live нельзя.
    """
    uid = gid = None
    try:
        with open(os.path.join(root, "etc/passwd")) as f:
            for line in f:
                fields = line.split(":")
                if len(fields) > 3 and fields[0] == name:
                    uid = int(fields[2])
                    gid = int(fields[3])
                    break
    except (OSError, ValueError):
        return None, None
    try:
        with open(os.path.join(root, "etc/group")) as f:
            for line in f:
                fields = line.split(":")
                if len(fields) > 2 and fields[0] == name:
                    gid = int(fields[2])
                    break
    except (OSError, ValueError):
        pass
    return uid, gid


def run():
    choice = libcalamares.globalstorage.value(GS_KEY)
    entry = SESSION_FILES.get(choice)
    if not entry:
        libcalamares.utils.debug(
            "сеанс не выбран ({}={!r}), оставляю выбор SDDM по умолчанию".format(
                GS_KEY, choice))
        return None

    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        libcalamares.utils.warning("нет rootMountPoint, пропускаю")
        return None

    session_dir, session_file = entry
    session_path = "/" + session_dir + "/" + session_file
    if not os.path.exists(os.path.join(root, session_dir.lstrip("/"), session_file)):
        libcalamares.utils.warning(
            "в целевой системе нет {}, пропускаю предвыбор сеанса".format(session_path))
        return None

    state_path = os.path.join(root, STATE_REL)
    os.makedirs(os.path.dirname(state_path), exist_ok=True)

    user = libcalamares.globalstorage.value("username") or ""
    lines = ["[Last]", "Session={}".format(session_path)]
    if user:
        lines.insert(1, "User={}".format(user))
    with open(state_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    # state.conf создаёт сам SDDM, и он должен принадлежать пользователю
    # sddm: иначе демон не сможет сохранить выбор после первого входа.
    os.chmod(state_path, 0o644)
    uid, gid = target_uid_gid(root, "sddm")
    if uid is not None and gid is not None:
        os.chown(state_path, uid, gid)
    else:
        libcalamares.utils.warning(
            "в целевой системе нет пользователя sddm, владельца не меняю")

    libcalamares.utils.debug(
        "сеанс {} → {}: {}".format(choice, state_path, " / ".join(lines)))
    return None
