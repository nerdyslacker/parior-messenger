ODIN ?= odin
SKALD_ROOT ?= vendor/skald
BAREV_ROOT ?= vendor/barev-odin
BUILD_DIR := build
APP := $(BUILD_DIR)/parior
PREFIX ?= /usr
DESTDIR ?=
BINDIR := $(PREFIX)/bin
DATADIR := $(PREFIX)/share
ICONDIR := $(DATADIR)/icons/hicolor/256x256/apps
DESKTOPDIR := $(DATADIR)/applications

ODIN_FLAGS := -collection:gui=$(SKALD_ROOT) -collection:barev=$(BAREV_ROOT) -define:ODIN_NBIO_QUEUE_SIZE=128

.PHONY: build release check style run install uninstall clean

build:
	mkdir -p $(BUILD_DIR)
	$(ODIN) build src $(ODIN_FLAGS) -debug -out:$(APP)

release:
	mkdir -p $(BUILD_DIR)
	$(ODIN) build src $(ODIN_FLAGS) -o:speed -out:$(APP)

check:
	$(ODIN) check src $(ODIN_FLAGS)

style:
	$(ODIN) check src $(ODIN_FLAGS) -strict-style -strict-style-packages:parior_messenger

run: build
	./$(APP)

install: release
	install -Dm755 $(APP) $(DESTDIR)$(BINDIR)/parior
	install -Dm644 assets/logo_256x256.png $(DESTDIR)$(ICONDIR)/parior.png
	install -Dm644 parior.desktop $(DESTDIR)$(DESKTOPDIR)/parior.desktop

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/parior
	rm -f $(DESTDIR)$(ICONDIR)/parior.png
	rm -f $(DESTDIR)$(DESKTOPDIR)/parior.desktop

clean:
	rm -f $(APP)
