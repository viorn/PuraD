# PuraD

Live-дистрибутив на базе чистого Debian: liveCD с KDE Plasma, установка на
ext4/btrfs из коробки, без сторонних репозиториев.

## Быстрый старт

```bash
# Собрать ISO для trixie
make iso TARGET=trixie

# Собрать ISO для sid
make iso TARGET=sid

# Проверить загрузку ISO в qemu (BIOS + UEFI)
make test TARGET=trixie

# Проверить, что в образе есть все прошивки Wi-Fi/GPU
make firmware TARGET=trixie

# Установить систему: VM с графикой + пустой диск 20G (builds/<target>/run/)
make run-install TARGET=trixie

# После установки — загрузиться с диска (без CD, иначе BIOS снова грузит live)
make run-installed TARGET=trixie

# Очистить артефакты (кэш пакетов сохраняется)
make clean

# Удалить всё, включая кэш сборки
make distclean

# Показать справку
make help
```

## Архитектура сборки

```
deked/
├── Makefile                  # make iso TARGET=trixie|sid
├── VERSION
├── container/
│   └── Dockerfile            # debian:{trixie,sid} + live-build
├── scripts/
│   ├── build.sh              # podman --privileged, bind-mount
│   ├── inside-build.sh       # lb config/bootstrap/chroot/binary внутри контейнера
│   ├── test-boot.sh          # headless-прогрев ISO по serial
│   ├── run-qemu.sh           # VM с графикой: посмотреть глазами
│   ├── check-firmware.sh     # состав прошивок в squashfs
│   └── gen-branding.sh       # SVG → PNG для Calamares
├── config/                   # дерево live-build
│   ├── common                # файл с LB_* переменными
│   ├── bootstrap             # файл: зеркало, дистрибутив, компоненты
│   ├── package-lists/
│   ├── hooks/
│   ├── includes.chroot/
│   ├── includes.binary/
│   └── bootloaders/
├── profiles/
│   ├── trixie.conf
│   └── sid.conf
├── builds/                   # артефакты (в .gitignore)
└── docs/
    ├── PLAN.md
    ├── build.md
    └── checklist-release.md
```

### Ключевые решения

- **live-build v3** — гибридный BIOS+UEFI ISO, squashfs-образ, checksums «из коробки»
- **Calamares** — GUI-установщик с выбором ext4/btrfs
- **Debian-installer не включается** (`--installer=false`) — экономия ~1 ГБ
- **KDE Plasma 6 Core** — `plasma-desktop` + базовые приложения
- **X11 жёстко** в live-сессии — Calamares гарантированно стартует
- **Сборка в podman** — изоляция, хостовые APT-источники не попадают в образ
- **Только официальные компоненты** — `main contrib non-free-firmware`
- **Один профиль различий** — trixie и sid собираются одним деревом конфига

### Wi-Fi охват

Набор задан явным списком `config/package-lists/400-firmware.list.chroot`
(`LB_FIRMWARE_CHROOT=false`): Intel, Atheros/ath10k/ath11k/ath12k, MediaTek mt76,
Realtek rtw88/rtw89, Broadcom brcm80211 и b43, Marvell libertas, ZyDAS zd1211,
IPW2x00, carl9170; из графики — amdgpu, i915/xe, Intel SOF.

Прошивки b43 скачиваются postinst-скриптом `firmware-b43-installer` **во время
сборки** (в контейнере есть сеть) и попадают в `/lib/firmware/b43` уже в ISO —
пользователю для Wi-Fi сеть не нужна.

Осознанно не включаем (сотни мегабайт ради серверных карт и nvidia):
`firmware-netronome`, `firmware-nvidia-graphics`, `firmware-marvell-prestera`,
`firmware-nvidia-tesla-535-gsp`, `firmware-bnx2*`, `firmware-cavium`,
`firmware-myricom`, `firmware-netxen`, `firmware-qlogic`, `firmware-siano`,
`firmware-liquidio`, `firmware-ast`, `firmware-cirrus`, `firmware-ivtv`.
Список проверяется `make firmware`.

> **Примечание:** `broadcom-sta-dkms` (wl.ko) и `rtl8821cu-dkms`
> отсутствуют в официальном архиве Debian — часть новых чипов
> потребует ручной доустановки после инсталла.

## Установщик: локальный apt-репозиторий на носителе

Шаг загрузчика в Calamares (`bootloader-config` из `calamares-settings-debian`)
ставит grub в целевую систему обычным apt:

```
chroot $CHROOT apt-get -y install grub-efi     # UEFI
chroot $CHROOT apt-get -y install grub-pc      # BIOS
```

В самой live-системе этих пакетов нет и быть не может: `grub-pc` и
`grub-efi-amd64` объявляют друг другу `Conflicts`, поэтому в образ нельзя
положить «оба сразу». А пока не отработал модуль `sources-final`, у целевой
системы единственный источник apt — сам носитель: `sources-media` пишет
`deb [trusted=yes] file:/run/live/medium trixie main`. Если на носителе пусто,
установка обрывается на загрузчике:

```
Package grub-efi is not available, but is referred to by another package.
E: Package 'grub-efi' has no installation candidate
```

`config/hooks/normal/0500-purad-installer-repo.binary` скачивает оба набора
(`grub-pc` для BIOS, `grub-efi` + цепочка `shim-signed` для UEFI), а также
`timeshift`, `inotify-tools` и `pkexec` для снимков btrfs. `pkexec`
скачивается принудительно (`--reinstall`): шаг `packages` удаляет его
`autoremove`-ом, а без него `apt-get install timeshift grub-btrfs pkexec`
падает целиком. `grub-btrfs` в Debian нет: хук собирает локальный `.deb` из
вендоренного тарбола (`vendor/grub-btrfs/`, версия и sha256 зафиксированы).
Всё это кладётся в `pool/main/`, индекс `dists/<target>/main/binary-amd64/`
с `Release` — рядом (сейчас ~27 `.deb`, ~8 МБ). Зависимости считаются по dpkg-статусу
**целевой** системы (`chroot/var/lib/dpkg/status`), а не контейнера сборки —
иначе apt пропустил бы пакеты, которые уже стоят в контейнере, но
отсутствуют в образе. Скачанные `.deb` кешируются в
`builds/<target>/cache/purad-installer-repo/`, так что пересборка без сети
тоже работает.

Итог: установка не требует интернета вплоть до `sources-final`, который
возвращает обычные зеркала Debian. Если понадобится ставить офлайн что-то ещё,
достаточно добавить имя пакета в `PACKAGE_GROUPS` этого хука (по одной группе
на строку; `grub-pc` и `grub-efi` — отдельно, они конфликтуют). `make
installer` предупреждает, если репозитория на носителе нет или в нём нет
пакетов снимков.

## Снимки btrfs

На установке с корнем на btrfs PuraD ставит Timeshift и grub-btrfs. Начальный
снимок создаётся при первом запуске установленной системы (в live-режиме
Timeshift снимки не делает) и содержит только корневой субтом `@`:
`/home`, `/var/log` и `/var/cache` — отдельные субтомы и в снимок не входят.
Расписание по умолчанию выключено — настройте его сами в Timeshift.

- Открыть Timeshift: меню приложений → Timeshift (или `timeshift-launcher`).
- Загрузиться в снимок: перезагрузиться, в меню GRUB выбрать
  «PuraD snapshots» → нужный снимок.
- Система из снимка стартует writable: изменения живут в RAM и пропадают при
  перезагрузке, сам снимок не меняется. Это режим восстановления, а не
  повседневная работа.
- `grub-btrfsd` обновляет меню GRUB, когда Timeshift создаёт новые снимки.

Снимки доступны только на btrfs. На ext4 Timeshift и grub-btrfs не
устанавливаются, initramfs-хуки не появляются, а юниты снимков не включаются:
файл `purad-first-snapshot.service` лежит в образе, но его условие на маркер
`/var/lib/purad/btrfs` не выполняется.

## Известные шероховатости установки

Проверено на живой установке (`make run-install`) и последующей загрузке
с диска — система ставится и стартует (GRUB → systemd → SDDM → Plasma).
Установка на btrfs даёт раскладку `@` / `@home` / `@log` / `@cache`
с `compress=zstd` в `/etc/fstab`; опции монтирования задаются в
`mount.conf` (`mountOptions`), а `fstab.conf` в Calamares 3.3 умеет только
`crypttabOptions`/`tmpOptions`.

В UEFI установщик дополнительно наполняет резервный путь `EFI/boot`
(shim + `grubx64.efi` + `mmx64.efi` + `grub.cfg`, модуль
`purad-efi-fallback`): система грузится, даже если прошивка потеряла запись
`PuraD` в NVRAM. Проверено на qemu/OVMF с чистым `OVMF_VARS`.

- **После установки VM снова грузит live-систему.** В режиме установки VM
  запускается с `-boot d` (CD первым), поэтому «Перезагрузить» в Calamares
  возвращает в live-сессию, а не в установленную систему. Это не ошибка
  установки: `make run-installed` поднимает ту же VM без CD и с `-boot c`.
- **Выключение live-системы после установки раньше висело ~90 секунд** —
  исправлено в этапе 7. Причин было две, обе в цепочке выключения live-сессии,
  а не в установке:
  - `sources-media -u` из `calamares-settings-debian` не снимал
    bind-монтирование носителя в целевом корне (точка монтирования искалась
    через `mount | grep … | cut`, после bind-монтирования вывод становился
    многострочным, путь получался пустым и `umount` уходил в корень цели).
    Заменено своим хелпером
    `config/includes.chroot/usr/share/calamares/helpers/calamares-sources-media`;
  - `live-medium-eject` из `live-tools` при `LIVE_MEDIUM_EJECT_VERBOSE=true`
    (умолчание) печатает приглашение и ждёт Enter на `/dev/console`, которого
    в графической сессии никто не нажмёт — ровно `DefaultTimeoutStopSec`.
    `config/includes.chroot/etc/live/tools.conf` выключает приглашение.

  Сейчас от `systemctl poweroff` до `reboot: Power down` проходит ~4 секунды.
  Сообщения `Failed to unmount /run/live/medium`,
  `Could not detach loop /dev/loop0`, `Cannot finalize remaining file systems,
  loop devices, continuing` в логе остаются — это носитель, который держит
  live-rootfs; на время выключения они не влияют.

## Кэш сборки

live-build кэширует bootstrap, chroot и скачанные `.deb` в
`builds/<target>/cache/`:

- `make clean` удаляет ISO и рабочие деревья, но **оставляет** кэш —
  следующая сборка не качает пакеты заново;
- `make distclean` удаляет всё, включая кэш;
- кэш раздельный для trixie и sid (разные релизы).

Для кэша, общего между профилями и проектами, можно поднять на хосте
[apt-cacher-ng](https://wiki.debian.org/AptCacherNg):

```bash
sudo apt install apt-cacher-ng
PURAD_APT_PROXY=http://host.containers.internal:3142 make iso TARGET=trixie
```

`host.containers.internal` — адрес хоста из rootless podman. Если прокси
недоступен, сборка просто обратится к зеркалу напрямую.

## Особенность rootless podman: `/dev` в chroot

`mknod` в rootless-контейнере запрещён (EPERM даже с `--privileged`),
поэтому debootstrap оставляет в `chroot/dev/` пустые обычные файлы вместо
устройств. Это не косметика: пакеты пишут в `/dev/null` как в файл, и запись
одного процесса ломает следующий. Так падала установка KDE на
`dictionaries-common` → `aspell-autobuildhash`:

```
aspell --per-conf=/dev/null ...        # rc=0, но aspell сохраняет в per-conf
                                       # строку "/usr/bin/aspell"
Error: /dev/null:1: The key "/usr/bin/aspell" is unknown.
```

Поэтому `scripts/inside-build.sh` разбивает `lb build` на
`lb bootstrap` → `lb chroot` → `lb binary` и на время стадий с postinst-скриптами
монтирует `/dev` контейнера в `chroot/dev` через `mount --rbind`
(нерекурсивный `--bind` не годится: в контейнере `/dev/null` — отдельный моунт
поверх tmpfs, и `--bind` подсунул бы вместо него файл-заглушку).

Если сборка упала посреди chroot-стадии, проще начать стадию с нуля:

```bash
PURAD_FORCE_CLEAN=1 make iso TARGET=trixie
```

См. [PLAN.md](docs/PLAN.md) для полного описания целей, архитектуры и этапов.
