#!/bin/bash
# scripts/gen-branding.sh — SVG-исходники брендинга → PNG для Calamares
#
# Calamares не умеет показывать SVG в branding, поэтому картинки рендерятся
# заранее и коммитятся в config/includes.chroot. Исходники — assets/branding/*.svg.
#
# Использование: scripts/gen-branding.sh   (нужен rsvg-convert или ImageMagick)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${REPO_DIR}/assets/branding"
DST="${REPO_DIR}/config/includes.chroot/etc/calamares/branding/purad"

if command -v rsvg-convert >/dev/null; then
    render() { rsvg-convert -o "$2" "$1"; }
elif command -v magick >/dev/null; then
    render() { magick -background none "$1" "$2"; }
else
    echo "ошибка: нужен rsvg-convert (librsvg2-bin) или ImageMagick" >&2
    exit 1
fi

mkdir -p "${DST}"
render "${SRC}/purad-logo.svg"    "${DST}/purad-logo.png"
render "${SRC}/purad-welcome.svg" "${DST}/welcome.png"
render "${SRC}/purad-slide1.svg"  "${DST}/slide1.png"

# Тот же логотип — иконкой приложения, на него ссылается
# /usr/share/applications/purad-install.desktop (Icon=purad-logo).
PIXMAPS="${REPO_DIR}/config/includes.chroot/usr/share/pixmaps"
mkdir -p "${PIXMAPS}"
cp -f "${DST}/purad-logo.png" "${PIXMAPS}/purad-logo.png"

ls -l "${DST}"/*.png "${PIXMAPS}/purad-logo.png"
