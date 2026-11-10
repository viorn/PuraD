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
- `firmware-b43-installer` скачивает прошивку на postinst: фиксируем результат
  через `includes.chroot`, чтобы в ISO файл попал без сети у пользователя.

### Фиксация X11 в live-сессии

- Автологин SDDM на сессию `plasmax11` (`/usr/share/xsessions/plasmax11.desktop`,
  `/usr/bin/startplasma-x11`, юнит `plasma-workspace-x11.target` — присутствуют
  в `plasma-workspace 6.3.6-2`).
- Выбор Wayland-сессии убирается из greeter (в live-режиме).
- Ограничение касается только live-сессии; на установленном диске SDDM предлагает
  обе сессии.

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
│   └── test-boot.sh          # qemu-прогрев ISO (BIOS и UEFI)
├── config/                   # дерево live-build
│   ├── common                # LB_ARCHITECTURES, LB_MODE, LB_BOOTLOADER, ...
│   ├── bootstrap             # зеркало, дистрибутив, компоненты
│   ├── package-lists/        # 000-base.list.chroot, 100-kde.list.chroot, ...
│   ├── hooks/                # chroot-хуки: брендинг, конфиги, systemd
│   ├── includes.chroot/      # /etc/skel KDE, /etc/calamares, polkit, /etc/os-release
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

### Этап 6. Calamares в live-образе

За основу — конфиги пакета `calamares-settings-debian`, поверх — свои
`settings.conf` и последовательность модулей, branding `PuraD` (рабочее имя; при
переименовании меняется только `branding/<name>.conf` и ярлык), polkit-правило,
ярлык «Установить PuraD» на рабочем столе.

**Готово, когда:** Calamares запускается из live-сессии (X11) без ручного ввода
пароля в терминале, проходит до шага разметки.

### Этап 7. Установка ext4/btrfs

- `partition.conf`: `defaultFileSystem: ext4`, btrfs в списке, GPT,
  EFI-раздел при UEFI;
- `mount.conf`: btrfs subvolumes `@` → `/`, `@home` → `/home`, `@log`, `@cache`;
- `fstab.conf`: `compress=zstd` для btrfs, корректные опции для ext4;
- `bootloader.conf`: GRUB для BIOS и UEFI.

**Готово, когда:** тестовые установки в qemu на btrfs и ext4 завершаются;
после перезагрузки: корректный `fstab`, раскладка subvolume (`@`, `@home`),
загрузчик стартует, `/home` на отдельном subvolume.

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

## 6. Версии в trixie (на момент планирования)

- live-build `1:20250505+deb13u1`, live-boot `1:20250815~deb13u1`,
  live-config `11.0.5`
- calamares `3.3.14-1` (Qt6, libkpmcore12), calamares-settings-debian `13.0.13-1`
- plasma-desktop `4:6.3.6-1`, plasma-workspace `4:6.3.6-2`, sddm `0.21.0+git20250502`
- firmware `20250410-2`
