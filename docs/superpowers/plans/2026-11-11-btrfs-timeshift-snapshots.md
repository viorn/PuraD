# Снимки btrfs: Timeshift + grub-btrfs — план реализации

> **Для агентов:** обязательный суб-скилл: `superpowers:executing-plans` (выбрано: реализация в этой сессии). Шаги отмечены чекбоксами.

**Цель:** на btrfs-установке PuraD поставить Timeshift и grub-btrfs, создать начальный снимок при первом запуске и обеспечить реальную загрузку в read-only снимок через overlayfs в initramfs.

**Архитектура:** при сборке ISO вендоренный grub-btrfs v4.14 собирается в локальный `.deb` и вместе с `timeshift`/`inotify-tools` кладётся в apt-репозиторий на носителе. Calamares-модуль `purad-snapshots` после шага `packages` определяет ФС целевого корня: на ext4 ничего не делает, на btrfs ставит пакеты, пишет конфиг Timeshift, ставит маркер и включает юниты. Первый запуск установленной системы создаёт снимок `@`, обновляет GRUB и выключает себя; загрузка в снимок поднимает overlayfs поверх read-only btrfs.

**Стек:** Debian trixie, live-build, Calamares 3.3 (Python-модули), systemd, Timeshift 24.06.6, grub-btrfs 4.14, initramfs-tools, overlayfs, btrfs.

**Спек:** `docs/superpowers/specs/2026-11-11-btrfs-timeshift-snapshots-design.md`

## Глобальные ограничения

- Только btrfs: на ext4 не устанавливаются `timeshift`, `grub-btrfs`, не создаются маркеры, не включаются юниты.
- Начальный снимок включает только `@`; `@home`, `@log`, `@cache` не включаются.
- Расписание снимков по умолчанию выключено (`schedule_* = "false"`).
- `timeshift` — из Debian `main`; `grub-btrfs` — вендоренный upstream v4.14, sha256 `4fe2f8a49b39e3e561fc51bbc5a0f81a7222c1e9ef8672e014e0ba3bedad20c6`.
- Пакет `grub-btrfs` версии `4.14-purad1`, `Architecture: all`, без maintainer-скриптов.
- Ошибка установки пакетов снимков не прерывает установку: `libcalamares.utils.warning(...)` и продолжение.
- Конфиг Timeshift использует строковые значения `"true"/"false"` (формат `/etc/timeshift/default.json`).
- Загрузка в снимок: `findmnt -no FSTYPE /` → `overlay`, снимок остаётся неизменным, изменения в RAM.

## Фокус ревью

1. **Повторный снимок при загрузке в снимок.** Если загрузиться в начальный снимок, в нём нет `first-snapshot.done`, а юнит включён. Скрипт обязан увидеть `findmnt -no FSTYPE / = overlay` и выйти, иначе создаст вложенный снимок.
2. **ext4 не должен получить артефакты.** На ext4 модуль обязан выйти до любых изменений; юниты и initramfs-хуки не должны появляться.
3. **Сбой установки пакетов не ломает установку.** Отсутствие сети/пакета в локальном репо — предупреждение, а не ошибка Calamares.
4. **Формат `timeshift.json`.** Булевы значения строками, `backup_device_uuid=""`, `btrfs_mode="true"`, `include_btrfs_home="false"`; иначе Timeshift уйдёт в rsync-режим или потребует устройство.
5. **Источник apt.** `purad-snapshots` должен ставить пакеты из локального репозитория на носителе, не полагаясь на сеть и не смешивая сетевые `sources.list`.

---

## Task 1: Вендоринг grub-btrfs и сборка `.deb`

**Файлы:**
- Создать: `vendor/grub-btrfs/grub-btrfs-v4.14.tar.gz`
- Создать: `vendor/grub-btrfs/README.md`
- Создать: `vendor/grub-btrfs/build-deb.sh`
- Создать: `vendor/grub-btrfs/initramfs-tools/hooks/grub-btrfs-overlay`
- Создать: `vendor/grub-btrfs/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay`
- Создать: `scripts/test-snapshots-deb.sh`

**Интерфейсы:**
- `build-deb.sh <output-dir>` создаёт `<output-dir>/grub-btrfs_4.14-purad1_all.deb`, проверяет sha256 тарбола.
- Пакет содержит: `/etc/grub.d/41_snapshots-btrfs`, `/etc/default/grub-btrfs/config`, `/usr/bin/grub-btrfsd`, `/usr/lib/systemd/system/grub-btrfsd.service`, man8, doc, два initramfs-скрипта.

- [ ] **Step 1: Написать падающий тест `scripts/test-snapshots-deb.sh`**

Тест должен:
- запустить `vendor/grub-btrfs/build-deb.sh` во временный каталог;
- проверить `dpkg-deb -f` для `Package: grub-btrfs`, `Version: 4.14-purad1`, `Architecture: all`, `Depends` содержит `btrfs-progs`, `inotify-tools`, `initramfs-tools`;
- проверить `dpkg-deb -c` для путей `etc/grub.d/41_snapshots-btrfs`, `etc/initramfs-tools/hooks/grub-btrfs-overlay`, `etc/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay`;
- проверить `sh -n` на обоих initramfs-скриптах;
- напечатать `PASS`/`FAIL` и вернуть код.

- [ ] **Step 2: Запустить тест и убедиться, что он падает**

Run: `bash scripts/test-snapshots-deb.sh`
Expected: FAIL — нет `vendor/grub-btrfs/build-deb.sh`.

- [ ] **Step 3: Скачать и зафиксировать тарбол**

Run:
```bash
mkdir -p vendor/grub-btrfs
curl -sL -o vendor/grub-btrfs/grub-btrfs-v4.14.tar.gz \
  https://github.com/Antynea/grub-btrfs/archive/refs/tags/v4.14.tar.gz
sha256sum vendor/grub-btrfs/grub-btrfs-v4.14.tar.gz
```
Expected: `4fe2f8a49b39e3e561fc51bbc5a0f81a7222c1e9ef8672e014e0ba3bedad20c6`.

- [ ] **Step 4: Написать `vendor/grub-btrfs/build-deb.sh`**

Установить файлы вручную (`install -Dm...`), не через `make install` (тот требует root и может вызвать `grub-mkconfig`). Добавить в `/etc/default/grub-btrfs/config` строку, включающую `ro` для снимков:
```sh
printf '\n# PuraD: boot snapshots read-only; the initramfs overlay makes them writable.\nGRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="ro"\n' >> "$pkgroot/etc/default/grub-btrfs/config"
```
Собрать `dpkg-deb --build --root-owner-group`.

- [ ] **Step 5: Написать initramfs-скрипты (адаптация PR #250)**

Хук: `manual_add_modules overlay`, `copy_exec /usr/bin/findmnt /usr/bin`, при наличии — `copy_exec` для `btrfs`.
Скрипт `local-bottom`: найти `btrfs`/`findmnt` среди `/usr/bin` и `/bin`; проверить `findmnt -no FSTYPE -M "$rootmnt" = btrfs` и `btrfs property get "$rootmnt" ro != ro=false`; при совпадении переместить корень, смонтировать tmpfs и overlayfs; при ошибке вернуть корень на место и продолжить загрузку read-only. Без `set -e`.

- [ ] **Step 6: Написать `vendor/grub-btrfs/README.md`**

Указать: upstream, тег, sha256, лицензию GPL-3.0, происхождение initramfs-скриптов (PR #250, автор Luis Marsano), почему вендорим (в Debian пакета нет, PR не влит), что скрипты адаптированы под usrmerge и Debian initramfs-tools.

- [ ] **Step 7: Запустить тест и убедиться, что он проходит**

Run: `bash scripts/test-snapshots-deb.sh`
Expected: PASS.

- [ ] **Step 8: Коммит**

```bash
chmod +x vendor/grub-btrfs/build-deb.sh scripts/test-snapshots-deb.sh \
  vendor/grub-btrfs/initramfs-tools/hooks/grub-btrfs-overlay \
  vendor/grub-btrfs/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay
git add vendor/grub-btrfs scripts/test-snapshots-deb.sh
git commit -m "vendor: grub-btrfs 4.14 и сборка локального .deb"
```

---

## Task 2: Локальный apt-репозиторий — timeshift, inotify-tools, grub-btrfs

**Файлы:**
- Изменить: `config/hooks/normal/0500-purad-installer-repo.binary`
- Изменить: `scripts/build.sh` (копирование `vendor/`, хэш)

**Интерфейсы:**
- Хук при сборке ISO кладёт в `binary/pool/main` пакеты `timeshift`, `inotify-tools`, `grub-btrfs_4.14-purad1_all.deb` и все недостающие зависимости; индекс `Packages`/`Release` обновляется.

- [ ] **Step 1: Написать падающую проверку**

В `scripts/test-boot.sh` в блоке `--installer` после проверки `REPO_DIR_IDX` добавить проверку:
```bash
for pkg in timeshift grub-btrfs inotify-tools; do
    grep -q "^Package: ${pkg}$" "${REPO_DIR_IDX}" || \
        echo "предупреждение: в локальном репозитории нет ${pkg}" >&2
done
```
Запустить тест на текущем образе: `bash scripts/test-boot.sh --installer` (или только синтаксис: `bash -n scripts/test-boot.sh`). Проверка должна предупредить об отсутствии пакетов.

- [ ] **Step 2: Изменить хук 0500**

- Заменить `PACKAGES="grub-pc grub-efi"` на группы, разделённые переводами строк: `grub-pc`, `grub-efi`, `timeshift inotify-tools` (grub-pc и grub-efi конфликтуют, поэтому отдельные прогоны apt).
- Убрать кэш-гейт `if [ -z "$(find ...)" ]`; выполнять `apt-get update -qq` и `apt-get -y -d install ...` для каждой группы всегда. Уже скачанные `.deb` apt не перекачивает.
- После загрузки вызвать `sh "${BUILD_DIR}/vendor/grub-btrfs/build-deb.sh" "${CACHE_DIR}/archives"`.
- Копирование `cp -f "${CACHE_DIR}"/archives/*.deb "${POOL}/"` оставить.

- [ ] **Step 3: Изменить `scripts/build.sh`**

После копирования `profiles` добавить:
```bash
rm -rf "${WORK_DIR}/vendor"
cp -a "${REPO_DIR}/vendor" "${WORK_DIR}/vendor"
```
В `BINARY_HASH` добавить `vendor`:
```bash
BINARY_HASH="$(hash_paths config/common config/bootloaders config/includes.binary profiles VERSION vendor)"
```

- [ ] **Step 4: Проверить сборку репозитория без полного ISO**

```bash
mkdir -p builds/trixie/vendor && cp -a vendor/. builds/trixie/vendor/
podman run --rm --privileged -v "$PWD/builds/trixie:/work:Z" -w /work/binary \
  -e LB_DISTRIBUTION=trixie -e LB_ARCHITECTURES=amd64 \
  localhost/purad-builder:trixie \
  sh /work/config/hooks/normal/0500-purad-installer-repo.binary
```
Expected: в `builds/trixie/binary/pool/main` есть `timeshift_*.deb`, `inotify-tools_*.deb`, `grub-btrfs_4.14-purad1_all.deb`; в `dists/trixie/main/binary-amd64/Packages` — записи о них.

- [ ] **Step 5: Коммит**

```bash
git add config/hooks/normal/0500-purad-installer-repo.binary scripts/build.sh scripts/test-boot.sh
git commit -m "repo: timeshift, inotify-tools и grub-btrfs на носителе"
```

---

## Task 3: Calamares-модуль `purad-snapshots`

**Файлы:**
- Создать: `config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots/main.py`
- Создать: `.../purad-snapshots/module.desc`
- Изменить: `config/includes.chroot/etc/calamares/settings.conf`
- Создать: `scripts/test-snapshots-module.py`

**Интерфейсы:**
- `target_root_fs(root, partitions) -> str`: `"btrfs"`, `"ext4"` или `""`; сначала ищет `partitions[*].mountPoint == "/"`, затем `etc/fstab` с `subvol=/@`.
- `write_timeshift_config(root)`: пишет `etc/timeshift/timeshift.json` на основе `default.json`.
- `run()`: на не-btrfs — debug и `None`; на btrfs — apt install, конфиг, маркер, `systemctl enable`.

- [ ] **Step 1: Написать падающий тест `scripts/test-snapshots-module.py`**

Тест подставляет заглушку `libcalamares` в `sys.modules`, импортирует `main.py` по пути и проверяет:
- btrfs-раздел → `target_root_fs(...) == "btrfs"`;
- ext4-раздел → `"ext4"`;
- без `partitions`, fstab с `subvol=/@` → `"btrfs"`;
- `write_timeshift_config` пишет `backup_device_uuid == ""`, `btrfs_mode == "true"`, `include_btrfs_home == "false"`, `do_first_run == "false"`, все `schedule_* == "false"`.

- [ ] **Step 2: Запустить тест и убедиться, что он падает**

Run: `python3 scripts/test-snapshots-module.py`
Expected: FAIL — модуль ещё не создан.

- [ ] **Step 3: Реализовать `main.py`**

Логика:
```python
def target_root_fs(root, partitions):
    for part in partitions or []:
        if part.get("mountPoint") == "/":
            return (part.get("fs") or "").lower()
    try:
        with open(os.path.join(root, "etc/fstab")) as f:
            for line in f:
                fields = line.split()
                if len(fields) >= 4 and fields[1] == "/" and fields[2] == "btrfs":
                    opts = fields[3]
                    if "subvol=/@" in opts or "subvol=@" in opts:
                        return "btrfs"
    except OSError:
        pass
    return ""
```
`install_packages(root)`:
- если существует `etc/apt/sources.list.d/debian-live-media.list`, добавить `-o Dir::Etc::sourcelist=/etc/apt/sources.list.d/debian-live-media.list -o Dir::Etc::sourceparts=-` (ставить только с носителя);
- `apt-get update`, затем `apt-get install -y --no-install-recommends timeshift grub-btrfs pkexec` через `libcalamares.utils.target_env_call(["/usr/bin/env", "DEBIAN_FRONTEND=noninteractive", "apt-get", ...])`;
- при ненулевом коде — `RuntimeError`.

`write_timeshift_config(root)` — читает `etc/timeshift/default.json`, обновляет ключи, пишет `timeshift.json`, `chmod 0644`.

`mark_btrfs(root)` — создаёт пустой `var/lib/purad/btrfs`.

`enable_units()` — `systemctl enable purad-first-snapshot.service grub-btrfsd.service`; ошибки — warning.

`run()` — `try/except`, при любой ошибке `libcalamares.utils.warning(...)`, вернуть `None`.

- [ ] **Step 4: Создать `module.desc`**

```yaml
type:       "job"
interface:  "python"
name:       "purad-snapshots"
script:     "main.py"
requiredModules: [ "partition", "mount" ]
```

- [ ] **Step 5: Добавить модуль в `settings.conf`**

После `- packages` добавить `- purad-snapshots` (до `plymouthcfg`/`initramfscfg`/`initramfs`).
**Важно:** в рабочем дереве уже есть незакоммиченные правки пользователя в `settings.conf` (purad-session) и `docs/PLAN.md`. Перед Task 3 убрать их в stash и вернуть только после коммита Task 5:
```bash
git stash push -- config/includes.chroot/etc/calamares/settings.conf docs/PLAN.md
# ... Task 3, Task 4, Task 5 (правки и коммиты) ...
git stash pop
```

- [ ] **Step 6: Запустить тест**

Run: `python3 scripts/test-snapshots-module.py && python3 -m py_compile config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots/main.py`
Expected: PASS.

- [ ] **Step 7: Коммит**

```bash
git add config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots \
  config/includes.chroot/etc/calamares/settings.conf scripts/test-snapshots-module.py
git commit -m "calamares: модуль purad-snapshots для btrfs"
```

---

## Task 4: Первый снимок и grub-btrfsd

**Файлы:**
- Создать: `config/includes.chroot/usr/lib/systemd/system/purad-first-snapshot.service`
- Создать: `config/includes.chroot/usr/lib/purad/first-snapshot`
- Создать: `config/includes.chroot/etc/systemd/system/grub-btrfsd.service.d/10-purad-timeshift.conf`

**Интерфейсы:**
- Юнит `purad-first-snapshot.service` включается только модулем на btrfs; при первом запуске создаёт снимок и выключает себя.
- Drop-in переопределяет `ExecStart` на `--syslog --timeshift-auto`.

- [ ] **Step 1: Написать падающую проверку**

Добавить в `scripts/test-snapshots-deb.sh` (или отдельный `scripts/test-snapshots-static.sh`) проверки:
- `test -f` всех трёх файлов;
- `sh -n` для `first-snapshot`;
- `grep -q 'ConditionPathExists=/var/lib/purad/btrfs'` в юните;
- `grep -q 'timeshift --create --btrfs --scripted --yes'` в скрипте;
- `grep -q 'findmnt -no FSTYPE /'` в скрипте (защита от вложенного снимка);
- `grep -q 'ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto'` в drop-in.

- [ ] **Step 2: Запустить и убедиться, что падает**

Expected: FAIL — файлов нет.

- [ ] **Step 3: Создать юнит**

```ini
[Unit]
Description=PuraD: initial btrfs snapshot
After=local-fs.target
Before=grub-btrfsd.service
ConditionPathExists=/var/lib/purad/btrfs
ConditionPathExists=!/var/lib/purad/first-snapshot.done

[Service]
Type=oneshot
ExecStart=/usr/lib/purad/first-snapshot
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 4: Создать `first-snapshot`**

```sh
#!/bin/sh
set -u

[ -f /var/lib/purad/btrfs ] || exit 0
[ -f /var/lib/purad/first-snapshot.done ] && exit 0
command -v timeshift >/dev/null 2>&1 || exit 0

# Загрузка в снимок: корень — overlayfs. Снимок уже есть, создавать нельзя.
[ "$(findmnt -no FSTYPE / 2>/dev/null)" = "btrfs" ] || exit 0

# Корень должен быть изменяемым btrfs (не read-only снимок).
[ "$(btrfs property get / ro 2>/dev/null)" = "ro=false" ] || exit 0

# Защита от потери маркера: снимок уже создан?
if timeshift --list --scripted 2>/dev/null | grep -Fq "PuraD: initial snapshot"; then
    touch /var/lib/purad/first-snapshot.done
    systemctl disable purad-first-snapshot.service >/dev/null 2>&1 || true
    exit 0
fi

if ! timeshift --create --btrfs --scripted --yes \
        --comments "PuraD: initial snapshot"; then
    echo "purad-first-snapshot: timeshift --create failed" >&2
    exit 1
fi

# Меню GRUB с пунктами снимков; ошибка не отменяет уже созданный снимок.
update-grub >/dev/null 2>&1 || echo "purad-first-snapshot: update-grub failed" >&2

touch /var/lib/purad/first-snapshot.done
systemctl disable purad-first-snapshot.service >/dev/null 2>&1 || true
exit 0
```

- [ ] **Step 5: Создать drop-in**

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto
```

- [ ] **Step 6: Запустить проверку**

Run: `bash scripts/test-snapshots-deb.sh`
Expected: PASS.

- [ ] **Step 7: Коммит**

```bash
chmod +x config/includes.chroot/usr/lib/purad/first-snapshot
git add config/includes.chroot/usr/lib/systemd/system/purad-first-snapshot.service \
  config/includes.chroot/usr/lib/purad/first-snapshot \
  config/includes.chroot/etc/systemd/system/grub-btrfsd.service.d/10-purad-timeshift.conf \
  scripts/test-snapshots-deb.sh
git commit -m "systemd: первый снимок btrfs и grub-btrfsd"
```

---

## Task 5: Документация

**Файлы:**
- Изменить: `docs/PLAN.md`
- Изменить: `README.md`

- [ ] **Step 1: Добавить этап 10 в `docs/PLAN.md`**

Описать: Timeshift + grub-btrfs только на btrfs; начальный снимок при первом запуске; overlayfs в initramfs для загрузки в снимок; вендоринг grub-btrfs как явная оговорка от «чистого Debian»; отсутствие `@var`; отсутствие расписания по умолчанию.

- [ ] **Step 2: Добавить раздел в `README.md`**

Пользовательский текст: «Снимки btrfs» — как открыть Timeshift, как загрузиться в снимок из GRUB, что изменения в снимке не сохраняются, что `@home` не входит в начальный снимок.

- [ ] **Step 3: Коммит**

```bash
git add docs/PLAN.md README.md
git commit -m "docs: снимки btrfs и загрузка в них"
```
**Важно:** `docs/PLAN.md` содержит незакоммиченные правки пользователя (purad-session); они должны быть в stash (см. Task 3, Step 5) и вернуться после коммита.

---

## Task 6: Интеграционная проверка

- [ ] **Step 1: Быстрые тесты**

```bash
bash scripts/test-snapshots-deb.sh
python3 scripts/test-snapshots-module.py
python3 -m py_compile config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots/main.py
bash -n scripts/build.sh scripts/test-boot.sh
sh -n config/includes.chroot/usr/lib/purad/first-snapshot
```
Expected: всё PASS.

- [ ] **Step 2: Собрать ISO**

Run: `make iso TARGET=trixie`
Expected: сборка завершается; в `builds/trixie/binary/pool/main` есть `timeshift_*.deb`, `inotify-tools_*.deb`, `grub-btrfs_4.14-purad1_all.deb`; в `Packages` — записи о них.

- [ ] **Step 3: Установка на btrfs (qemu)**

Run: `make run-install TARGET=trixie`
В Calamares: btrfs, установка. После установки:
```bash
dpkg -l timeshift grub-btrfs
ls /etc/initramfs-tools/hooks/grub-btrfs-overlay
ls /etc/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay
lsinitramfs /boot/initrd.img-$(uname -r) | grep grub-btrfs-overlay
systemctl status grub-btrfsd --no-pager
systemctl status purad-first-snapshot --no-pager
timeshift --list
grep -c 'timeshift-btrfs' /boot/grub/grub-btrfs.cfg
```
Expected: пакеты установлены; скрипты в initramfs; `grub-btrfsd` active; `purad-first-snapshot` done; `timeshift --list` показывает снимок с комментарием `PuraD: initial snapshot`; в `grub-btrfs.cfg` есть пункт снимка.

- [ ] **Step 4: Загрузка в снимок (qemu)**

Перезагрузиться, в меню GRUB выбрать снимок. В системе:
```bash
findmnt -no FSTYPE /
mount | grep -E 'overlay|btrfs'
```
Expected: `overlay`; в `mount` виден `lowerdir` с путём снимка; сессия Plasma запускается; созданный файл исчезает после перезагрузки.

- [ ] **Step 5: Установка на ext4 (qemu)**

Повторить установку с ext4. Expected: `dpkg -l timeshift grub-btrfs` — не установлены; нет initramfs-хуков; `systemctl is-enabled grub-btrfsd purad-first-snapshot` — not-found/disabled; `timeshift` отсутствует.

- [ ] **Step 6: Финальный коммит (если были правки по итогам проверки)**

```bash
git add -A
git commit -m "test: проверки снимков btrfs и загрузки в них"
```