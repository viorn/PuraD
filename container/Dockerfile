# container/Dockerfile — окружение сборки PuraD
#
# Базовый образ выбирается таргетом, чтобы версии live-build/dpkg в контейнере
# соответствовали целевому релизу (см. docs/PLAN.md, раздел 2).
#
#   podman build --build-arg BASE=debian:trixie -t purad-builder:trixie -f container/Dockerfile .
#   podman build --build-arg BASE=debian:sid    -t purad-builder:sid    -f container/Dockerfile .

ARG BASE=debian:trixie
FROM ${BASE}

ENV DEBIAN_FRONTEND=noninteractive

# live-build — основной инструмент сборки.
# debootstrap — построение базового дерева.
# squashfs-tools — filesystem.squashfs.
# xorriso, isolinux, syslinux-common — гибридный ISO и BIOS-загрузчик.
# grub-efi-amd64-bin — UEFI-загрузчик.
# mtools, dosfstools — EFI-образ (FAT).
# ca-certificates, curl — HTTPS-зеркала; git — вспомогательные операции.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        live-build \
        debootstrap \
        squashfs-tools \
        xorriso \
        isolinux \
        syslinux-common \
        grub-efi-amd64-bin \
        mtools \
        dosfstools \
        git \
        ca-certificates \
        curl \
        wget \
        sudo \
        fakeroot \
    && rm -rf /var/lib/apt/lists/*

# live-build должен собираться от root: монтирует proc/sys/dev в chroot.
WORKDIR /work

CMD ["/bin/bash"]
