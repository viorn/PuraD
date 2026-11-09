.PHONY: help clean iso

TARGET ?= trixie
VERSION := $(shell cat VERSION)
BUILD_DIR := builds/$(TARGET)
ISO_NAME := PuraD-$(TARGET)-$(VERSION).iso

help:
	@echo "PuraD — Live-дистрибутив на базе Debian"
	@echo
	@echo "Использование:"
	@echo "  make iso TARGET=trixie|sid   — собрать ISO"
	@echo "  make clean                   — удалить артефакты сборки"
	@echo "  make help                    — показать эту справку"
	@echo
	@echo "Версия: $(VERSION)"
	@echo "Целевой профиль: $(TARGET)"

iso:
	@bash scripts/build.sh $(TARGET)

clean:
	rm -rf $(BUILD_DIR)
