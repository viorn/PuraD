.PHONY: help iso clean clean-images

TARGET ?= trixie
VERSION := $(shell cat VERSION)
BUILD_DIR := builds/$(TARGET)
ISO := $(BUILD_DIR)/PuraD-$(TARGET)-$(VERSION)-amd64.hybrid.iso

help:
	@echo "PuraD — Live-дистрибутив на базе Debian"
	@echo
	@echo "Использование:"
	@echo "  make iso TARGET=trixie|sid   — собрать ISO"
	@echo "  make clean                   — удалить артефакты сборки (builds/)"
	@echo "  make clean-images            — удалить образы сборщика podman"
	@echo "  make help                    — показать эту справку"
	@echo
	@echo "Версия: $(VERSION)"
	@echo "Целевой профиль: $(TARGET)"

iso:
	@bash scripts/build.sh $(TARGET)

# В rootless podman часть файлов в chroot создаётся под subuid-пользователями
# контейнера (например, _apt), поэтому из хостового пользователя `rm` упирается
# в «Отказано в доступе». Удаляем деревья внутри user namespace podman.
clean:
	@if [ -d builds ]; then \
		podman unshare rm -rf builds 2>/dev/null || rm -rf builds; \
	fi

clean-images:
	-podman rmi localhost/purad-builder:trixie localhost/purad-builder:sid
