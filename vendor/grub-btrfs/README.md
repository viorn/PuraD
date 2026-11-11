# vendor/grub-btrfs

Вендоренный исходник `grub-btrfs` для сборки локального `.deb` при сборке
ISO. В Debian пакета `grub-btrfs` нет ни в одном компоненте, а сторонние
APT-репозитории и GPG-ключи проект не использует.

## Что лежит

| Файл | Происхождение |
|---|---|
| `grub-btrfs-v4.14.tar.gz` | upstream-тарбол `Antynea/grub-btrfs`, тег `v4.14` |
| `initramfs-tools/hooks/grub-btrfs-overlay` | адаптация `initramfs/ubuntu/hooks/grub-btrfs-overlay` из PR #250 |
| `initramfs-tools/scripts/local-bottom/grub-btrfs-overlay` | адаптация `initramfs/ubuntu/scripts/local-bottom/grub-btrfs-overlay` из PR #250 |
| `build-deb.sh` | сборка локального `.deb` |

## Фиксация версии

- Версия пакета: `4.14-purad1`.
- sha256 тарбола:
  `4fe2f8a49b39e3e561fc51bbc5a0f81a7222c1e9ef8672e014e0ba3bedad20c6`.
- `build-deb.sh` проверяет sha256 перед сборкой и падает при несовпадении.

## Лицензия

`grub-btrfs` распространяется под GPL-3.0-or-later (см. `LICENSE` в
тарболе). Скрипты initramfs-tools из PR #250 — тот же GPL-3.0; автор
адаптации в PR — Luis Marsano.

## Почему initramfs-скрипты вендорены отдельно

В upstream-релизе v4.14 есть только initramfs-скрипты для Arch Linux
(mkinitcpio). Для Debian/Ubuntu они находятся в открытом PR #250, который
не влит в upstream. Без них загрузка в read-only снапшот Timeshift
заканчивается read-only корнем: `systemd.volatile=state` не делает корень
writable (upstream issue #331), а отдельный `@var` не нужен, если поднять
overlayfs поверх всего корня.

Отличия адаптации от PR #250:

- POSIX `sh`, без bash-специфики;
- поиск `btrfs`, `findmnt` и `mktemp` и в `/usr/bin`, и в `/bin` — в
  Debian с usrmerge hook `btrfs-progs` кладёт бинарник в `/usr/bin`;
- при ошибке overlay корень возвращается на место, загрузка продолжается
  read-only, а не падает в panic;
- `GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="ro"` добавляется в конфиг
  пакета: снапшот грузится read-only, writable-слой даёт только overlay.

## Сборка

```sh
vendor/grub-btrfs/build-deb.sh <output-dir>
```

`<output-dir>/grub-btrfs_4.14-purad1_all.deb` кладётся в локальный
APT-репозиторий на носителе хуком
`config/hooks/normal/0500-purad-installer-repo.binary`.