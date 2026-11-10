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
│   └── test-boot.sh          # qemu-прогрев ISO
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

Полный набор firmware-пакетов: Intel, Atheros, Broadcom b43, Realtek,
MediaTek, rtw88/rtw89, mt76, IPW2x00, zd1211, libertas, carl9171.

> **Примечание:** `broadcom-sta-dkms` (wl.ko) и `rtl8821cu-dkms`
> отсутствуют в официальном архиве Debian — часть новых чипов
> потребует ручной доустановки после инсталла.

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
