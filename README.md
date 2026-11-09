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

# Очистить артефакты
make clean

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
│   ├── package-lists/chroot/
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

См. [PLAN.md](docs/PLAN.md) для полного описания целей, архитектуры и этапов.
