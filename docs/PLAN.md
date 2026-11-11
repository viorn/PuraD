# PuraD — план проекта

> **Рабочее название дистрибутива — PuraD.** Название рабочее: оно может остаться,
> а может быть заменено позже. Репозиторий пока лежит в `deked/`, поэтому путь каталога
> и имя каталога сборки не меняем; на бренд внутри образа (Calamares, загрузчик,
> `/etc/os-release`) ставим PuraD, и при переименовании правим только его.

Live-дистрибутив на базе чистого Debian: liveCD с KDE Plasma, установка на ext4/btrfs
из коробки, без сторонних репозиториев. Первая цель — Debian 13 (trixie), затем профиль
для sid.

## 1. Цели и принципы

- **Чистый Debian.** Только официальные компоненты архива (`main`, `contrib`,
  `non-free-firmware`). Никаких `config/archives/*` в live-build, никаких сторонних
  GPG-ключей. `non-free-firmware` — официальный компонент Debian с релиза 12,
  использование прошивок из него не нарушает пуризм.
- **Воспроизводимость.** Все конфиги live-build лежат в git; сборка даёт идентичный
  результат на любой машине с тем же профилем и снимком архива.
- **Изоляция сборки.** Сборка только внутри контейнера (`podman`), хостовые APT-источники
  не должны иметь шансов попасть в образ.
- **Один профиль различий.** trixie и sid собираются одним деревом конфига; расхождения
  релизов вынесены в `profiles/<codename>.conf`.

## 2. Ключевые решения

| Область | Решение | Обоснование |
|---|---|---|
| Инструмент сборки | `live-build` (v3, `lb config`/`lb build`) | Официальный инструмент Debian: гибридный BIOS+UEFI ISO, live-boot + overlayfs, checksums, манифесты «из коробки» |
| Установщик | Calamares 3.3.x | GUI-выбор ext4/btrfs, btrfs-subvolume раскладка `@`/`@home`, брендинг; d-i кастомизировать под это несоизмеримо дороже |
| debian-installer | не включаем (`--installer=false`) | экономия ~1 ГБ и один слой сложности |
| Среда | KDE Plasma 6 (состав Core) | `plasma-desktop` + базовые приложения, без `kde-full` |
| Сессия live-CD | **X11, жёстко** | надёжнее Wayland на произвольном железе/драйверах; Calamares гарантированно стартует (pkexec/polkit, DISPLAY). На установленном диске Wayland остаётся доступным |
| Компоненты архива | `main contrib non-free-firmware` | contrib нужен для b43-обвязки; non-free-firmware — для Wi-Fi/GPU/NVMe |
| Wi-Fi | максимальный охват firmware-пакетами | без прошивок в live-CD починить сеть на живом системе невозможно |
| Сборка | `podman` + `debian:trixie` / `debian:sid` | версия live-build/dpkg соответствует целевому релизу; хост не пачкается |
| Sid | пиннинг apt на снимок `snapshot.debian.org` | sid в произвольный момент может быть несобираемым; снимок даёт воспроизводимость |
| Имя дистрибутива | **PuraD** (рабочее) | может измениться; бренд изолирован в `branding/`, `/etc/os-release` и теме загрузчика, переименование — одна правка |
| Снимки btrfs | Timeshift + grub-btrfs, overlayfs в initramfs | только btrfs; загрузка в RO-снимок реально работает, `@var` не нужен (этап 10) |

### Состав Core (v1)

`plasma-workspace`, `sddm`, `dolphin`, `konsole`, `firefox-esr`, `systemsettings`,
`plasma-nm`, `xdg-desktop-portal-kde`, `okular`, `ark`, шрифты, Breeze.
Без persistence, Secure Boot, arm64 и собственного APT-репозитория — это кандидаты v2.

### Охват Wi-Fi

Пакеты: `firmware-iwlwifi`, `firmware-atheros`, `firmware-ath9k-htc`,
`firmware-brcm80211`, `firmware-misc-nonfree` (rtw88/rtw89/mt76), `firmware-realtek`,
`firmware-mediatek` (mt7921/mt7925), `firmware-ipw2x00`, `firmware-zd1211`,
`firmware-libertas`, `firmware-carl9171`, плюс contrib-обвязка
`firmware-b43-installer` / `firmware-b43legacy-installer`, и стек
`iw wpasupplicant wireless-regdb rfkill network-manager plasma-nm`.

Ограничения (осознанные):

- `broadcom-sta-dkms` (wl.ko) и `rtl8821cu-dkms` в официальном архиве Debian
  отсутствуют — часть новых чипов потребует ручной доустановки после инсталла;
  в образ не кладём, чтобы не нарушать «чистый Debian».
- `firmware-b43-installer` скачивает прошивку в postinst: он выполняется во
  время сборки (в контейнере есть сеть), поэтому в ISO прошивка уже лежит и
  вендорить бинарники в `includes.chroot` не нужно.

### Фиксация X11 в live-сессии

- Автологин SDDM на сессию `plasmax11` (`/usr/share/xsessions/plasmax11.desktop`,
  `/usr/bin/startplasma-x11`, юнит `plasma-workspace-x11.target` — присутствуют
  в `plasma-workspace 6.3.6-2`).
- Выбор Wayland-сессии убирается из greeter (в live-режиме).
- Ограничение касается только live-сессии; на установленном диске SDDM предлагает
  обе сессии, а установщик спрашивает, какую сделать сеансом по умолчанию
  (этап 7, `packagechooser@session`).

Реализация — компонент live-config
`config/includes.chroot/usr/lib/live/config/0086-purad-live-x11`: он выполняется
после штатного `0085-sddm` и перекрывает его, записывая
`/etc/sddm.conf.d/zz-purad-live-x11.conf` (`[Autologin] Session=plasmax11`)
и переименовывая `/usr/share/wayland-sessions/*.desktop` в `*.disabled`.
Штатный `0085-sddm` выбирает `Session=` по `realpath $(which x-session-manager)`,
а `x-session-manager` может указывать на Wayland-сессию, поэтому полагаться
на него нельзя.

## 3. Структура репозитория

```
deked/                        # каталог репозитория; имя дистрибутива — PuraD
├── Makefile                  # make iso TARGET=trixie|sid, make clean
├── VERSION
├── container/
│   └── Dockerfile            # debian:{trixie,sid} + live-build и зависимости сборки
├── scripts/
│   ├── build.sh              # podman --privileged, bind-mount, том apt-кэша
│   ├── inside-build.sh       # lb config/bootstrap/chroot/binary внутри контейнера
│   ├── test-boot.sh          # qemu-прогрев ISO (BIOS и UEFI)
│   └── check-firmware.sh     # состав прошивок в squashfs (make firmware)
├── config/                   # дерево live-build
│   ├── common                # LB_ARCHITECTURES, LB_MODE, LB_BOOTLOADER, ...
│   ├── bootstrap             # зеркало, дистрибутив, компоненты
│   ├── package-lists/        # 000-base, 100-kde, 400-firmware
│   ├── preseed/              # ответы debconf (лицензия firmware-ipw2x00)
│   ├── hooks/                # chroot-хуки: брендинг, конфиги, systemd
│   ├── includes.chroot/      # /etc/skel KDE, /etc/calamares, polkit, live-config
│   ├── includes.binary/      # тема загрузчика
│   └── bootloaders/          # grub-efi + isolinux
├── profiles/
│   ├── trixie.conf
│   └── sid.conf              # только различия релиза
├── builds/                   # артефакты (в .gitignore)
└── docs/
    ├── PLAN.md               # этот файл
    ├── build.md              # пошаговая инструкция сборки
    └── checklist-release.md  # проверки перед релизом
```

Принципы: один конфиг — два релиза; никаких `config/archives/`; итеративная сборка
через кэш bootstrap/chroot live-build.

## 4. Этапы

### Этап 1. Каркас проекта

git init, каталоги, `VERSION`, `Makefile`, `.gitignore`, README с описанием
архитектуры сборки.

**Готово, когда:** `make help` работает, структура каталогов на месте.

### Этап 2. Контейнерный сборщик

`container/Dockerfile`: `debian:trixie`/`debian:sid` + `live-build`, `debootstrap`,
`squashfs-tools`, `xorriso`, `isolinux`, `grub-efi-amd64-bin`, `syslinux-common`,
`mtools`, `dosfstools`, `git`, `ca-certificates`.
`scripts/build.sh`: `podman --privileged`, bind-mount проекта, том для apt-кэша,
артефакты в `builds/`.

**Готово, когда:** `lb config && lb build` выполняется внутри контейнера
(пока хотя бы на минимальном конфиге).

### Этап 3. Минимальный live-образ

`config/common`, `config/bootstrap`: зеркало `deb.debian.org`, компоненты
`main contrib non-free-firmware`, `--installer=false`, `--mode debian`.
Пакеты: `linux-image-amd64`, `live-boot`, `live-config-systemd`.
Проверка загрузки в qemu (при отсутствии — установить `qemu-system-x86` и `ovmf`):
`scripts/test-boot.sh <target> --all` (он же `make test`). В bootappend добавлены
`console=tty0 console=ttyS0,115200n8`, чтобы live-сессия была видна в headless-qemu;
вход — умолчания live-config (`user` / `live`).

**Готово, когда:** ISO грузится в qemu (BIOS и UEFI) до shell live-сессии.
Оба режима проверены: `make test TARGET=trixie`.

### Этап 4. KDE Plasma 6 (Core) + X11

Списки пакетов KDE, хук автологина live-сессии с фиксацией X11
(SDDM `Session=plasmax11`, скрыть выбор сессий), отключение нежелательных сервисов
(baloo, krdisplaydrc и т.п. по ситуации), `/etc/skel` с пресетами Plasma
(панель, тема Breeze, нет first-run wizard).

**Готово, когда:** live-образ загружается в Plasma на X11 с автологином;
`echo $XDG_SESSION_TYPE` → `x11`; Wayland в списке сессий live-режима недоступен.

Состав Core и фиксация X11 описаны в разделах «Состав Core» и «Фиксация X11
в live-сессии». Проверено `make test TARGET=trixie` (BIOS и UEFI):
SDDM автологинит `user` в сессию `Type=x11` (`/usr/share/xsessions/plasmax11.desktop`),
`/usr/share/wayland-sessions/plasma.desktop` переименован в `.disabled`.
Пресеты Plasma в `/etc/skel` — только `baloofilerc`; панель/тема/first-run
wizard ещё не настроены.

### Этап 5. Максимальный охват Wi-Fi

См. раздел «Охват Wi-Fi». Проверка: распаковка `filesystem.squashfs` из ISO и
наличие ожидаемых `.rbf/.fw/.dat` в `/lib/firmware`; в live-сессии `iw dev` видит
беспроводной интерфейс (в qemu — через usb-wifi проброшенным устройством либо
проверка по содержимому squashfs).

**Готово, когда:** все firmware из списка в образе, NetworkManager поднимает Wi-Fi
в live-сессии.

Реализация: `config/package-lists/400-firmware.list.chroot` + беспроводной стек,
`LB_FIRMWARE_CHROOT=false` (иначе live-build тянет все `firmware-*` архива,
включая серверные NIC и nvidia). b43 закрыт пакетами `firmware-b43*-installer`:
их postinst скачивает прошивку во время сборки, в ISO файлы уже лежат.
Проверка — `make firmware TARGET=trixie` (`scripts/check-firmware.sh`):
читает список файлов `filesystem.squashfs` и требует хотя бы один файл на
каждое семейство (iwlwifi, ath10k/11k/12k, mt76, rtw88/89, brcm80211, b43,
libertas, zd1211, ipw2x00, amdgpu, i915/xe, SOF) плюс пакеты стека.

### Этап 6. Calamares в live-образе

За основу — конфиги пакета `calamares-settings-debian`, поверх — свои
`settings.conf` и последовательность модулей, branding `PuraD` (рабочее имя; при
переименовании меняется только `branding/<name>.conf` и ярлык), polkit-правило,
ярлык «Установить PuraD» на рабочем столе.

**Готово, когда:** Calamares запускается из live-сессии (X11) без ручного ввода
пароля в терминале, проходит до шага разметки.

**Реализация:**

- `config/package-lists/300-installer.list.chroot` — `calamares` +
  `calamares-settings-debian`; последовательность модулей взята из дистрибутива,
  комментарии переведены, branding переключён на `purad`
  (`config/includes.chroot/etc/calamares/settings.conf`);
- branding — `config/includes.chroot/etc/calamares/branding/purad/`
  (`branding.desc`, `show.qml` со `slideshowAPI: 2`, PNG). Исходники —
  `assets/branding/*.svg`, в PNG рендерит `scripts/gen-branding.sh` (QML
  SVG не умеет);
- `usr/lib/live/config/0087-purad-calamares` — правило polkit для live-пользователя
  на **два** action id: `org.freedesktop.policykit.exec` и
  `com.github.calamares.calamares.pkexec.run` (Calamares объявляет собственный
  action, generic-правила для pkexec недостаточно);
- `usr/bin/purad-installer` — обёртка: прячет live-`/etc/fstab`
  (`# UNCONFIGURED FSTAB FOR BASE SYSTEM`) и запускает `pkexec /usr/bin/calamares`;
- ярлык «Установить PuraD»: `usr/share/applications/purad-install.desktop` +
  `usr/bin/purad-installer-icon` из `/etc/xdg/autostart`, который кладёт его на
  рабочий стол только при загрузке с носителя (`/run/live`);
- **локальный apt-репозиторий на носителе** — `config/hooks/normal/0500-purad-installer-repo.binary`.
  Шаг `bootloader-config` ставит grub обычным `apt-get install grub-efi|grub-pc`
  из целевой системы, а до модуля `sources-final` единственный источник — сам
  носитель. Без `pool/` установка падает с
  `E: Package 'grub-efi' has no installation candidate`;
- `scripts/test-boot.sh --installer` — проверка запуска Calamares из live-сессии
  по serial-консоли (pkexec, XAUTHORITY, отсутствие «Not authorized»).

### Этап 7. Установка ext4/btrfs

- `partition.conf`: `defaultFileSystemType: ext4`, btrfs в списке,
  `initialSwapChoice: none`, EFI-раздел при UEFI;
- `mount.conf`: btrfs subvolumes `@` → `/`, `@home` → `/home`, `@log`,
  `@cache`; опции монтирования (`noatime`, `compress=zstd`, `umask=0077` для EFI);
- `fstab.conf`: только то, что читает Calamares 3.3 (`crypttabOptions`,
  `tmpOptions`) — опции монтирования приходят из `mount.conf`;
- `bootloader.conf`: GRUB для BIOS и UEFI;
- убрать зависание выключения live-системы после установки.

**Готово, когда:** тестовые установки в qemu на btrfs и ext4 завершаются;
после перезагрузки: корректный `fstab`, раскладка subvolume (`@`, `@home`),
загрузчик стартует, `/home` на отдельном subvolume.

**Реализация** (`config/includes.chroot/etc/calamares/modules/*.conf`):
Debian не поставляет `partition.conf`, поэтому он наш; остальные три — копии
конфигов `calamares-settings-debian` без лишних ключей.

- GPT на BIOS **не форсируется**: `requiredPartitionTableType` в `partition.conf`
  только фильтрует уже существующие таблицы и на авторазаметку не влияет —
  `PartitionActions::doAutopartition` жёстко берёт `partType = isEfi ? gpt : msdos`.
  GPT на BIOS требовал бы `bios_grub`-раздела, которого Calamares не создаёт.
- `fstab.conf` сокращён до `crypttabOptions` + `tmpOptions`: `mountOptions` и
  `ssdExtraMountOptions` — это Calamares 3.2, в 3.3 они не читаются (схема
  `fstab.schema.yaml` с `additionalProperties: false` ругалась на них). Опции
  берутся из `mountOptions` в `mount.conf` через `mountOptionsList` в global storage.
- `config/includes.chroot/usr/share/calamares/helpers/calamares-sources-media` —
  замена одноимённого хелпера из `calamares-settings-debian` (см. ниже).
- `config/includes.chroot/etc/live/tools.conf` — `LIVE_MEDIUM_EJECT_VERBOSE=false`.
- свой модуль Calamares `purad-efi-fallback` (шаг сразу после `bootloader`) —
  доделывает резервный путь загрузки UEFI. Calamares при
  `installEFIFallback: true` копирует в `EFI/boot` только сам загрузчик
  (`grubx64.efi` → `bootx64.efi`) и не кладёт `grub.cfg`. Прошивка, потерявшая
  запись в NVRAM, уходила в приглашение `grub>` (проверено на qemu с чистым
  `OVMF_VARS`). Модуль раскладывает `EFI/boot` как `grub-install --removable`:
  shim первым этапом, `grubx64.efi`, `mmx64.efi` и `grub.cfg` из каталога
  загрузчика (`EFI/PuraD`).
- выбор сеанса Plasma по умолчанию: страница `packagechooser@session`
  (`packagechooser-session.conf`, Wayland/X11) в фазе `show` и модуль
  `purad-session` в `exec` сразу после `displaymanager`. Ключа «сессия по
  умолчанию» в `/etc/sddm.conf` нет; SDDM 0.21 берёт предвыбор из
  `[Last] Session=` в `/var/lib/sddm/state.conf` (`sddm-state.conf(5)`:
  «preselected when the login screen shows up») и после удачного входа
  обновляет его сам (`RememberLastSession`). Модуль пишет
  `Session=plasmax11.desktop` или `plasma.desktop` и владельца `sddm`
  по `/etc/passwd` **целевой** системы (uid в live и в цели не обязан
  совпадать). Экземпляр `packagechooser` нужен потому, что ключ global
  storage — `packagechooser_<id экземпляра>`, а ключ `id:` внутри конфига
  Calamares 3.3 не читает.

**Зависание выключения — две независимые причины:**

1. `sources-media -u` не снимал bind-монтирование носителя. Хелпер Debian искал
   точку монтирования через `mount | grep $path | cut -f3 -d' '`; после
   bind-монтирования в chroot вывод становился многострочным и `MEDIUM_PATH`
   оказывался пустым, поэтому `-u` выполнял `umount $CHROOT/` (корень цели,
   занят) и bind-монтирование оставалось жить до самого shutdown. Наш хелпер
   ищет точку через `mountpoint -q` по списку известных путей и снимает именно
   `$CHROOT$MEDIUM_PATH`.
2. `live-medium-eject` (из `live-tools`, вызывается
   `/usr/lib/systemd/system-shutdown/live-tools.shutdown`) при
   `LIVE_MEDIUM_EJECT_VERBOSE=true` (умолчание) печатает приглашение и делает
   `read x < /dev/console` — ждёт Enter, которого в графической сессии никто не
   нажмёт. Через `DefaultTimeoutStopSec` это давало ровно ~90 c (в замерах —
   до 206 c). `tools.conf` выключает приглашение; лоток по-прежнему открывается
   в фоне.

**Проверено** (qemu, BIOS и UEFI, `qemu-img`/`debugfs`/`mtools` по образу
диска и загрузка установленной системы):

- ext4: `/etc/fstab` → `UUID=… / ext4 defaults,noatime 0 1`,
  `grub.cfg` → `menuentry 'PuraD GNU/Linux'`, `GRUB_DISTRIBUTOR='PuraD'`;
  диск — `dos`, один раздел 24 GiB;
- btrfs: subvolume `@`, `@home`, `@log`, `@cache`; `/etc/fstab`:
  `subvol=/@`, `subvol=/@home`, `subvol=/@log`, `subvol=/@cache` —
  все с `defaults,noatime,compress=zstd`, `pass=0`; файловая система
  монтируется с `zstd` (видно в `dmesg`);
- UEFI (`OVMF`): GPT, ESP 512 МиБ FAT32 (`/boot/efi` с `defaults,umask=0077`),
  `/etc/fstab` с теми же `subvol=/@…,compress=zstd`; на ESP —
  `EFI/PuraD/{shimx64,grubx64,mmx64,fbx64}.efi` + `grub.cfg` с
  `prefix=($root)'/@/boot/grub'` и заполненный `EFI/boot`
  (`bootx64.efi`=shim, `grubx64.efi`, `mmx64.efi`, `grub.cfg`);
  в NVRAM создаётся запись `PuraD` → `\EFI\PuraD\shimx64.efi`;
- после перезагрузки: GRUB → systemd → SDDM (Plasma/Wayland) → Plasma —
  проверено в BIOS и в UEFI, в UEFI дважды: с сохранённым NVRAM (запись
  `PuraD`) и со сброшенным NVRAM (загрузка через `\EFI\BOOT\BOOTX64.EFI`);
- выключение live-сессии после установки: от `systemctl poweroff` до
  `reboot: Power down` — ~4 c вместо 90–206 c. Остаются косметические
  `Failed to unmount /run/live/medium`, `Could not detach loopback /dev/loop0`
  (носитель держит сам live-rootfs) — на время выключения не влияют.

### Этап 8. Профиль sid

`profiles/sid.conf`, сборка в контейнере `debian:sid`, пиннинг apt на снимок
`snapshot.debian.org` (через `config/archives/*.pref.chroot` + pin по origin;
live-build не поддерживает `config/apt/preferences.chroot`).
Устранение расхождений: имена пакетов KDE, live-boot, calamares.

**Готово, когда:** sid-ISO грузится, Calamares проходит установку так же, как trixie.

### Этап 9. Воспроизводимый цикл

Цели `make iso TARGET=trixie|sid`, `make clean`; sha256-суммы и пакет манифеста
в `builds/`; `docs/build.md` и `docs/checklist-release.md`.

**Готово, когда:** полная пересборка с нуля на чистой машине повторяет результат
по инструкциям из docs без ручных шагов вне Makefile.

### Этап 10. Снимки btrfs (Timeshift + grub-btrfs)

- Только btrfs: Calamares-модуль `purad-snapshots` после `packages`
  определяет ФС целевого корня; на ext4 выходит, ничего не устанавливая и
  не включая.
- `timeshift` скачивается из Debian `main` при сборке ISO. `grub-btrfs` в
  Debian отсутствует, поэтому upstream v4.14 вендорится в
  `vendor/grub-btrfs/` (sha256 тарбола зафиксирован) и собирается в локальный
  `.deb` хуком `0500-purad-installer-repo.binary`. Сторонних APT-репозиториев
  и GPG-ключей нет; это единственная явная оговорка от принципа «чистый
  Debian».
- Начальный снимок создаёт `purad-first-snapshot.service` при первом запуске
  установленной системы: Timeshift в live-режиме отказывается создавать
  снимки (`boot=live` в `/proc/cmdline`). Снимок содержит только `@`;
  `@home`, `@log`, `@cache` — отдельные субтомы. Расписание по умолчанию
  выключено.
- Загрузка в снимок: `grub-btrfsd` (`--timeshift-auto`) обновляет меню GRUB,
  а initramfs-tools-хук из пакета поднимает overlayfs поверх read-only
  снимка. Система стартует writable, изменения живут в RAM и пропадают при
  перезагрузке, сам снимок не меняется. Отдельный `@var` не нужен.
- Хук — адаптация upstream PR #250 (GPL-3.0, не влит в upstream; только
  Arch-скрипты есть в релизе). Поэтому загрузка в снимок обязательна к
  проверке в qemu на trixie; фолбэк — отдельный `@var` отдельной задачей.

**Готово, когда:** на btrfs в qemu после установки есть начальный снимок, в
GRUB есть пункты снимков, загрузка в снимок даёт `findmnt -no FSTYPE /` =
`overlay`; на ext4 Timeshift, grub-btrfs, initramfs-хуки и их юниты
отсутствуют.

## 5. Риски

1. **Calamares + Wayland** — снят фиксацией X11 в live-сессии (Этап 4).
2. **Размер ISO** ~4–5 ГБ из-за firmware-набора. Фолбэк: вариант `core-lite`.
3. **Sid mid-transition** — пиннинг на snapshot.debian.org (Этап 8), иначе сборка
   невоспроизводима.
4. **Rootless podman**: `--privileged` может не дать монтировать proc/sys в chroot.
   Фолбэк: rootful podman. Отдельная ловушка — `mknod` в rootless-контейнере
   запрещён, поэтому в `chroot/dev` нет устройств и `/dev/null` — обычный файл;
   лечится `mount --rbind /dev chroot/dev` на время chroot-стадии
   (`scripts/inside-build.sh`, подробности в README).
5. **b43**: postinst требует сеть; фиксируем прошивку в includes (Этап 5).
6. **Plasma 6 в sid**: переходные версии (6.3 → 6.x) могут менять зависимости;
   лечится пиннингом снимка.
7. **grub-btrfs и overlayfs-хук — не из Debian.** Вендоренный grub-btrfs
   v4.14 и initramfs-скрипты из невлитого upstream PR #250. Проверка загрузки
   в снимок на trixie в qemu обязательна; фолбэк — отдельный `@var`
   (отдельная задача).

## 6. Версии в trixie (на момент планирования)

- live-build `1:20250505+deb13u1`, live-boot `1:20250815~deb13u1`,
  live-config `11.0.5`
- calamares `3.3.14-1` (Qt6, libkpmcore12), calamares-settings-debian `13.0.13-1`
- plasma-desktop `4:6.3.6-1`, plasma-workspace `4:6.3.6-2`, sddm `0.21.0+git20250502`
- firmware `20250410-2`
