.PHONY: help iso test clean distclean clean-images

TARGET ?= trixie
VERSION := $(shell cat VERSION)
BUILD_DIR := builds/$(TARGET)
ISO := $(BUILD_DIR)/PuraD-$(TARGET)-$(VERSION)-amd64.hybrid.iso

help:
	@echo "PuraD — Live-дистрибутив на базе Debian"
	@echo
	@echo "Использование:"
	@echo "  make iso TARGET=trixie|sid   — собрать ISO"
	@echo "  make test TARGET=trixie|sid  — загрузить ISO в qemu (BIOS+UEFI)"
	@echo "  make clean                   — удалить артефакты, СОХРАНИТЬ кэш сборки"
	@echo "  make distclean               — удалить всё, включая кэш и ISO"
	@echo "  make clean-images            — удалить образы сборщика podman"
	@echo "  make help                    — показать эту справку"
	@echo
	@echo "Версия: $(VERSION)"
	@echo "Целевой профиль: $(TARGET)"

iso:
	@bash scripts/build.sh $(TARGET)

test:
	@bash scripts/test-boot.sh $(TARGET) --all --desktop

# `clean` удаляет рабочие деревья и ISO, но СОХРАНЯЕТ builds/<target>/cache
# (bootstrap, chroot, скачанные .deb) — следующая сборка идёт из кэша.
# Полное удаление — `make distclean`.
#
# В rootless podman часть файлов в chroot создаётся под subuid-пользователями
# контейнера (например, _apt), поэтому из хостового пользователя `rm` упирается
# в «Отказано в доступе». Удаляем деревья внутри user namespace podman.
clean:
	@if [ -d builds ]; then \
		podman unshare bash -c 'for d in builds/*/; do \
			[ -d "$$d" ] || continue; \
			find "$$d" -mindepth 1 -maxdepth 1 ! -name cache -exec rm -rf {} +; \
		done' 2>/dev/null || rm -rf builds; \
	fi

distclean:
	@if [ -d builds ]; then \
		podman unshare rm -rf builds 2>/dev/null || rm -rf builds; \
	fi

clean-images:
	-podman rmi localhost/purad-builder:trixie localhost/purad-builder:sid
