# Снимки btrfs: Timeshift + grub-btrfs и загрузка в снимки

- Дата: 2026-11-11
- Статус: реализовано (2026-11-11)
- Связанные документы: `docs/PLAN.md`, `README.md`,
  `docs/superpowers/plans/2026-11-11-btrfs-timeshift-snapshots.md`

## 1. Цель

На установке PuraD с корнем на btrfs:

1. поставить Timeshift в целевую систему;
2. сразу после первого запуска установленной системы создать начальный снимок;
3. поставить grub-btrfs, чтобы снимки были доступны в меню GRUB;
4. **обеспечить реальную загрузку в read-only снимок**: система должна
   стартовать writable, изменения — жить в RAM и пропадать при перезагрузке.

На ext4 ни Timeshift, ни grub-btrfs, ни их юниты в установленной системе не
появляются.

## 2. Принципы и границы

- **Только btrfs.** Вся функциональность включается модулем Calamares после
  определения файловой системы целевого корня. На ext4 модуль ничего не делает.
- **Чистый Debian с одной явной оговоркой.** `.deb` `timeshift` скачивается
  из `main` Debian при сборке ISO и кладётся в локальный репозиторий на
  носителе. `grub-btrfs` в Debian отсутствует, поэтому upstream-исходник
  фиксированной версии вендорится в репозиторий и собирается в локальный `.deb`
  при сборке ISO. Сторонних APT-репозиториев и GPG-ключей нет; версия и
  sha256 тарбола зафиксированы. Оговорка документируется в `docs/PLAN.md`.
- **Загрузка в снимок — через overlayfs в initramfs, а не через `@var`.**
  Это сохраняет неизменность снимка и делает корень writable на время сессии.
  Отдельный `@var` не нужен и в этой задаче не добавляется.
- **Начальный снимок — при первом запуске установленной системы, а не в
  установщике.** Timeshift отказывается создавать снимки в live-режиме:
  `App.live_system()` проверяет `/proc/cmdline` на `boot=live` / `boot=casper`
  и возвращает ошибку «Snapshots cannot be created in Live CD mode».
- **Опциональная функция не ломает установку.** Если пакеты снимков не удалось
  поставить, модуль пишет предупреждение в лог Calamares и продолжает
  установку; проверка это ловит отдельно.
- **Никакого расписания снимков по умолчанию.** Пользователь настраивает его
  сам через GUI Timeshift.

## 3. Решения

### 3.1. Вендоринг grub-btrfs и сборка `.deb`

- В репозиторий добавляется `vendor/grub-btrfs/`:
  - `grub-btrfs-v4.14.tar.gz` — upstream-тарбол с GitHub,
    sha256 `4fe2f8a49b39e3e561fc51bbc5a0f81a7222c1e9ef8672e014e0ba3bedad20c6`;
  - `initramfs-tools/` — два скрипта overlayfs из upstream-PR #250
    (адаптированы под POSIX sh и usrmerge, атрибуция и GPL-3.0 в README);
  - `README.md` — происхождение, версии/коммиты, sha256, лицензии, причина
    вендоринга (в Debian пакета нет; PR не влит в upstream).
- `.deb` собирается из тарбола и вендоренных скриптов при сборке ISO, а не
  хранится в git. Пакет содержит:
  - `/etc/grub.d/41_snapshots-btrfs` (755);
  - `/etc/default/grub-btrfs/config` (644);
  - `/usr/bin/grub-btrfsd` (744);
  - `/usr/lib/systemd/system/grub-btrfsd.service` (644);
  - `/etc/initramfs-tools/hooks/grub-btrfs-overlay` (755) — добавляет модуль
    `overlay` и копирует `findmnt`/`btrfs` в initramfs;
  - `/etc/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay` (755) —
    при read-only btrfs-корне монтирует overlayfs;
  - man-страницы `grub-btrfs(8)`, `grub-btrfsd(8)`;
  - `README.md` и `LICENSE` в `/usr/share/doc/grub-btrfs/`.
- `DEBIAN/control`: `Package: grub-btrfs`, `Version: 4.14-purad1`,
  `Architecture: all`, `Depends: btrfs-progs, grub-common, bash (>= 4),
  gawk | mawk, inotify-tools, initramfs-tools`. Maintainer-скриптов нет:
  пакет не должен запускать `update-grub`/`update-initramfs` в live-chroot;
  initramfs перегенерирует штатный модуль Calamares `initramfs`, который идёт
  после `packages`.
- Сборка — `dpkg-deb --build --root-owner-group` (в контейнере сборки
  `dpkg-deb` уже есть; `fakeroot` не требуется).
- Хук `config/hooks/normal/0500-purad-installer-repo.binary` расширяется
  (он уже владеет локальным репозиторием на носителе):
  - в список скачиваемых пакетов добавляются `timeshift`, `inotify-tools` и
    `pkexec`;
  - `pkexec` качается отдельно с `--reinstall`: шаг `packages` удаляет его
    `autoremove`-ом, но в dpkg-статусе сборочного chroot он есть, поэтому
    обычный `apt-get -d install pkexec` счёл бы его установленным и не
    скачал. Без `pkexec` в репозитории атомарный
    `apt-get install timeshift grub-btrfs pkexec` падает целиком, и Timeshift
    не ставится;
  - из вендоренных исходников собирается `grub-btrfs_4.14-purad1_all.deb`;
  - все `.deb` копируются в `pool/main`, индекс `Packages`/`Release`
    генерируется как сейчас;
  - кэш-гейт «если в `cache/purad-installer-repo/archives` есть хоть один
    `.deb` — ничего не качать» заменяется на нормальную логику: онлайн
    `apt-get -d` запускается всегда, а уже скачанные `.deb` apt не
    перекачивает; офлайн (индекс не скачался) хук использует кэш, но только
    если в нём есть все верхнеуровневые пакеты (`grub-pc`, `grub-efi`,
    `timeshift`, `inotify-tools`, `pkexec`). Иначе сборка падает с внятной
    ошибкой.
- `scripts/build.sh` копирует `vendor/` в рабочее дерево и включает его в
  отпечаток сборки, иначе изменение тарбола не приведёт к пересборке.

### 3.2. Модуль Calamares `purad-snapshots`

Новый python-модуль по образцу `purad-efi-fallback`:

- каталог:
  `config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots/`
  (`main.py`, `module.desc`);
- в `settings.conf` добавляется в фазу `exec` сразу после `packages`, до
  `initramfscfg`/`initramfs` и до `sources-media-unmount`/`sources-final`.
  Это важно: initramfs-хук из пакета должен попасть в initramfs, который
  перегенерирует следующий штатный шаг `initramfs`;
- определяет ФС целевого корня: `rootPartition` + `partitions` из global
  storage, фолбэк — наличие `subvol=/@` в `<root>/etc/fstab`;
- **ext4:** пишет debug-сообщение и выходит, ничего не меняя;
- **btrfs:**
  1. `apt-get update` и `apt-get install -y --no-install-recommends timeshift
     grub-btrfs pkexec` в целевом chroot (`DEBIAN_FRONTEND=noninteractive`).
     `pkexec` нужен GUI-обёртке Timeshift (`timeshift-launcher`). В образе он
     есть как зависимость `calamares-settings-debian`, но этот пакет шаг
     `packages` удаляет, а `autoremove` добивает `pkexec`; поэтому он лежит в
     репозитории на носителе и ставится явно;
  2. пишет `/etc/timeshift/timeshift.json` на основе поставленного пакетом
     `/etc/timeshift/default.json`: `do_first_run=false`, `btrfs_mode=true`,
     `include_btrfs_home=false`, все `schedule_*=false`,
     `backup_device_uuid=""` (в btrfs-режиме Timeshift сам берёт системный
     диск с сабтомом `@`);
  3. создаёт маркер `/var/lib/purad/btrfs`;
  4. включает `purad-first-snapshot.service` и `grub-btrfsd.service`
     (`systemctl enable` в целевом chroot);
- при ошибке установки пакетов — `libcalamares.utils.warning(...)` и
  продолжение установки.

### 3.3. Первый запуск

- `config/includes.chroot/usr/lib/systemd/system/purad-first-snapshot.service`:
  - `Type=oneshot`, `After=local-fs.target`, `Before=grub-btrfsd.service`;
  - условия: существует `/var/lib/purad/btrfs`, отсутствует
    `/var/lib/purad/first-snapshot.done`;
  - `ExecStart=/usr/lib/purad/first-snapshot`, `RemainAfterExit=yes`;
  - `WantedBy=multi-user.target` (включается только модулем на btrfs).
- `config/includes.chroot/usr/lib/purad/first-snapshot`:
  1. проверяет маркер btrfs и наличие `timeshift`;
  2. не создаёт снимок, если `findmnt -no FSTYPE /` не `btrfs` (загрузка в
     снимок даёт `overlay`) или `btrfs property get / ro` не `ro=false` — это
     защита от вложенного снимка при загрузке в начальный снимок, где
     `done`-маркера нет;
  3. если снимка с комментарием `PuraD: initial snapshot` ещё нет —
     `timeshift --create --btrfs --scripted --yes
     --comments "PuraD: initial snapshot" --tags O`;
  4. `update-grub`; при ошибке `done` не ставится, юнит повторит только
     `update-grub` при следующей загрузке (снимок не дублируется);
  5. `touch /var/lib/purad/first-snapshot.done`;
  6. `systemctl disable purad-first-snapshot.service`.
- Юнит и скрипт лежат в образе всегда, но на ext4 не включены и не срабатывают.

### 3.4. grub-btrfsd

- В образе лежит drop-in
  `config/includes.chroot/etc/systemd/system/grub-btrfsd.service.d/10-purad-timeshift.conf`:
  ```
  [Service]
  ExecStart=
  ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto
  ```
- `--timeshift-auto` нужен для Timeshift ≥ 22.06 (у нас 24.06.6), который
  монтирует снимки в `/run/timeshift/<pid>/backup/timeshift-btrfs`.
- Drop-in безвреден на ext4: юнита `grub-btrfsd.service` там нет.

### 3.5. Загрузка в read-only снимок (overlayfs в initramfs)

- `/etc/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay` выполняется
  после монтирования корня, до `run-init`. Если корень — btrfs и
  `btrfs property get <root> ro` ≠ `ro=false` (то есть это read-only снимок),
  скрипт:
  1. переносит смонтированный корень в `lower_dir`;
  2. монтирует tmpfs и создаёт `upper`/`work`;
  3. монтирует overlayfs (`lowerdir=снимок`, `upperdir/workdir` в RAM) на
     место корня.
- Итог: система стартует как writable, все изменения — в RAM и теряются при
  перезагрузке; сам снимок остаётся неизменным.
- Нормальная загрузка не затрагивается: у `@` свойство `ro=false`.
- В GRUB-пункт снимка добавляется
  `GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="ro systemd.mask=systemd-remount-fs.service"`.
  `ro` не даёт монтировать снимок rw; `systemd-remount-fs` маскируется, потому
  что overlayfs не принимает remount с опциями из `/etc/fstab`
  (`EINVAL: no changes allowed in reconfigure`), а корень уже writable через
  overlay. Маска действует только на снимках.
- `@var` не нужен: writable становится весь корень, включая `/var`.
- Хук попадает в initramfs, который перегенерирует Calamares-модуль
  `initramfs` после установки пакета. Начальный снимок создаётся уже после
  этого, поэтому содержит initramfs с хуком. Снимки, сделанные до установки
  хука, overlay не получат — в нашей схеме таких нет.
- Рассмотренные альтернативы: `systemd.volatile=state` (не делает корень
  writable, issue grub-btrfs #331) и отдельный `@var` (ломает согласованность
  `/`/`/var`, не нужен при overlayfs).

## 4. Поток

1. `make iso` → хук 0500 кладёт в `pool/main` пакеты `timeshift`,
   `inotify-tools`, `pkexec`, их недостающие зависимости и собранный
   `grub-btrfs`.
2. Calamares на btrfs: `packages` → `purad-snapshots` (apt install + конфиг +
   маркер + enable) → `initramfscfg` → `initramfs` (хук overlay попадает в
   initramfs) → `sources-media-unmount` → `sources-final`.
3. Первая загрузка установленной системы: `purad-first-snapshot` создаёт
   снимок, обновляет GRUB, ставит маркер и выключает себя.
4. Дальше `grub-btrfsd` обновляет меню при новых снимках Timeshift.
5. Выбор снимка в GRUB → initramfs видит read-only btrfs и поднимает
   overlayfs → система стартует writable в RAM.
6. На ext4 шаг 2 ничего не делает; шаги 3–5 не активны.

## 5. Проверка

- **Сборка:** в `pool/main` есть `grub-btrfs_4.14-purad1_all.deb`, `timeshift`,
  `inotify-tools`, `pkexec`; `Packages`/`Release` содержат их.
- **Установка на btrfs (qemu):** `dpkg -l timeshift grub-btrfs`; в
  `/etc/initramfs-tools/{hooks,scripts/local-bottom}/` лежат
  `grub-btrfs-overlay`; после `update-initramfs` они есть в initramfs
  (`lsinitramfs`); после первой загрузки `timeshift --list` показывает
  начальный снимок; в `/boot/grub/` есть `grub-btrfs.cfg`, в `grub.cfg` —
  пункты снимков; `systemctl status grub-btrfsd` — active;
  `purad-first-snapshot` — done.
- **Загрузка в снимок (qemu):** выбрать пункт снимка в GRUB;
  `findmnt -no FSTYPE /` → `overlay`; `mount | grep btrfs` показывает снимок
  в `lowerdir`; рабочий стол/сессия запускаются; изменения не переживают
  перезагрузку.
- **Установка на ext4 (qemu):** `timeshift` и `grub-btrfs` не установлены,
  initramfs-хуков нет, `grub-btrfsd.service` и
  `purad-first-snapshot.service` не включены.

## 6. Ограничения и риски

- **Снимок без `@home`.** Начальный снимок включает только `@` (система).
  `@home` не включаем; пользователь может включить это в GUI Timeshift.
- **Автоматического расписания нет.** Только начальный снимок и ручные.
- **Overlayfs-хук — из открытого PR #250, не из релиза.** Код GPL-3.0,
  вендорится с атрибуцией и адаптируется; обязательна проверка на trixie в
  qemu. Если хук не сработает — фолбэк на отдельный `@var` (отдельная задача).
- **grub-btrfs — не из Debian.** Явная, локализованная оговорка от принципа
  «чистый Debian»; версия и исходник зафиксированы.
- **Timeshift в live-режиме снимки не делает** — это ожидаемо и не лечится.
- **Повтор первого снимка.** Снимок не дублируется: скрипт ищет комментарий
  `PuraD: initial snapshot` в `timeshift --list`; если снимок уже есть, а
  `done`-маркера нет, повторяется только `update-grub`.

## 7. Вне скоупа

- расписание снимков (hourly/daily/boot) и политика хранения;
- включение `@home` в снимки;
- отдельный `@var` (не нужен при overlayfs; только как фолбэк);
- снимки/восстановление из live-сессии;
- шифрование (LUKS) и Secure Boot;
- переименование или брендирование Timeshift;
- загрузка в снимки, созданные до установки overlayfs-хука.