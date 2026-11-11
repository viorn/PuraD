# Снимки btrfs: Timeshift + grub-btrfs

- Дата: 2026-11-11
- Статус: на вычитке
- Связанные документы: `docs/PLAN.md`, `README.md`

## 1. Цель

На установке PuraD с корнем на btrfs:

1. поставить Timeshift в целевую систему;
2. сразу после первого запуска установленной системы создать начальный снимок;
3. поставить grub-btrfs, чтобы снимки были доступны в меню GRUB.

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
  - `README.md` — происхождение, версия, sha256, лицензия GPL-3.0, причина
    вендоринга (в Debian пакета нет).
- `.deb` собирается из тарбола при сборке ISO, а не хранится в git.
  Пакет содержит:
  - `/etc/grub.d/41_snapshots-btrfs` (755);
  - `/etc/default/grub-btrfs/config` (644);
  - `/usr/bin/grub-btrfsd` (744);
  - `/usr/lib/systemd/system/grub-btrfsd.service` (644);
  - man-страницы `grub-btrfs(8)`, `grub-btrfsd(8)`;
  - `README.md` и `LICENSE` в `/usr/share/doc/grub-btrfs/`.
- `DEBIAN/control`: `Package: grub-btrfs`, `Version: 4.14-purad1`,
  `Architecture: all`, `Depends: btrfs-progs, grub-common, bash (>= 4),
  gawk | mawk, inotify-tools`. Maintainer-скриптов нет: пакет не должен
  запускать `update-grub` и трогать загрузчик в live-chroot.
- Сборка — `dpkg-deb --build --root-owner-group` (в контейнере сборки
  `dpkg-deb` уже есть; `fakeroot` не требуется).
- Хук `config/hooks/normal/0500-purad-installer-repo.binary` расширяется
  (он уже владеет локальным репозиторием на носителе):
  - в список скачиваемых пакетов добавляются `timeshift` и `inotify-tools`;
  - из вендоренного тарбола собирается `grub-btrfs_4.14-purad1_all.deb`;
  - все `.deb` копируются в `pool/main`, индекс `Packages`/`Release`
    генерируется как сейчас;
  - кэш-гейт «если в `cache/purad-installer-repo/archives` есть хоть один
    `.deb` — ничего не качать» заменяется на нормальную логику: `apt-get -d`
    запускается всегда, а уже скачанные `.deb` apt не перекачивает.
- `scripts/build.sh` копирует `vendor/` в рабочее дерево и включает его в
  отпечаток сборки, иначе изменение тарбола не приведёт к пересборке.

### 3.2. Модуль Calamares `purad-snapshots`

Новый python-модуль по образцу `purad-efi-fallback`:

- каталог:
  `config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots/`
  (`main.py`, `module.desc`);
- в `settings.conf` добавляется в фазу `exec` сразу после `packages`, пока
  локальный репозиторий носителя ещё смонтирован (до
  `sources-media-unmount`/`sources-final`);
- определяет ФС целевого корня: `rootPartition` + `partitions` из global
  storage, фолбэк — наличие `subvol=/@` в `<root>/etc/fstab`;
- **ext4:** пишет debug-сообщение и выходит, ничего не меняя;
- **btrfs:**
  1. `apt-get update` и `apt-get install -y --no-install-recommends timeshift
     grub-btrfs pkexec` в целевом chroot (`DEBIAN_FRONTEND=noninteractive`).
     `pkexec` нужен GUI-обёртке Timeshift (`timeshift-launcher`); в образе он
     уже есть как зависимость `calamares-settings-debian`, но перечисляем
     явно, чтобы `--no-install-recommends` не оставил GUI без запуска;
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
  2. `timeshift --create --btrfs --scripted --yes
     --comments "PuraD: initial snapshot" --tags O`;
  3. `update-grub` (best-effort: ошибка логируется, снимок уже создан);
  4. `touch /var/lib/purad/first-snapshot.done`;
  5. `systemctl disable purad-first-snapshot.service`.
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

## 4. Поток

1. `make iso` → хук 0500 кладёт в `pool/main` пакеты `timeshift`,
   `inotify-tools`, их недостающие зависимости и собранный `grub-btrfs`.
2. Calamares на btrfs: `packages` → `purad-snapshots` (apt install + конфиг +
   маркер + enable) → `sources-media-unmount` → `sources-final`.
3. Первая загрузка установленной системы: `purad-first-snapshot` создаёт
   снимок, обновляет GRUB, ставит маркер и выключает себя.
4. Дальше `grub-btrfsd` обновляет меню при новых снимках Timeshift.
5. На ext4 шаг 2 ничего не делает; шаги 3–4 не активны.

## 5. Проверка

- **Сборка:** в `pool/main` есть `grub-btrfs_4.14-purad1_all.deb`, `timeshift`,
  `inotify-tools`; `Packages`/`Release` содержат их.
- **Установка на btrfs (qemu):** `dpkg -l timeshift grub-btrfs`; после первой
  загрузки `timeshift --list` показывает начальный снимок; в `/boot/grub/`
  есть `grub-btrfs.cfg`, в `grub.cfg` — пункты снимков;
  `systemctl status grub-btrfsd` — active; `purad-first-snapshot` — done.
- **Установка на ext4 (qemu):** `timeshift` и `grub-btrfs` не установлены,
  `grub-btrfsd.service` и `purad-first-snapshot.service` не включены.
- **Загрузка в снимок:** отдельная ручная проверка; см. ограничение в §6.

## 6. Ограничения и риски

- **Снимок без `@home`.** Начальный снимок включает только `@` (система).
  `@home` не включаем; пользователь может включить это в GUI Timeshift.
- **Автоматического расписания нет.** Только начальный снимок и ручные.
- **`@var` не добавляется.** Для работы Timeshift/grub-btrfs он не нужен.
  Он нужен только для надёжной загрузки в read-only снимок с графикой:
  KDE/SDDM и `AccountsService` пишут в `/var/lib`, а при текущей раскладке
  `/var` (кроме `@log` и `@cache`) остаётся read-only. Надёжный путь
  восстановления — Timeshift из обычной системы или live-носителя. Если
  понадобится загрузка в снимок — отдельная задача: `@var` либо overlayfs-хук
  в initramfs (рекомендуемый вариант).
- **grub-btrfs — не из Debian.** Явная, локализованная оговорка от принципа
  «чистый Debian»; версия и исходник зафиксированы.
- **Timeshift в live-режиме снимки не делает** — это ожидаемо и не лечится.
- **Возможны дубли при сбое первого снимка.** Если снимок создан, а маркер не
  записан, повторный запуск создаст ещё один снимок. Допустимо для v1;
  отметить в документации.

## 7. Вне скоупа

- расписание снимков (hourly/daily/boot) и политика хранения;
- включение `@home` в снимки;
- отдельный `@var` и overlayfs-хук initramfs;
- снимки/восстановление из live-сессии;
- шифрование (LUKS) и Secure Boot;
- переименование или брендирование Timeshift.