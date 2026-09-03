PREFIX ?= /usr/local
DESTDIR ?=
APP_DIR := $(DESTDIR)$(PREFIX)/share/learn-omarchy
BIN_DIR := $(DESTDIR)$(PREFIX)/bin
DESKTOP_DIR := $(DESTDIR)$(PREFIX)/share/applications

.PHONY: check test install uninstall

check:
	npm run check

test:
	npm test

install:
	install -d "$(APP_DIR)" "$(APP_DIR)/assets/characters/hexon" "$(BIN_DIR)" "$(DESKTOP_DIR)"
	cp -R app courses experiments src tools package.json "$(APP_DIR)/"
	cp -R assets/characters/hexon/sprites "$(APP_DIR)/assets/characters/hexon/"
	install -m 755 bin/hexon-lab "$(BIN_DIR)/hexon-lab"
	install -m 755 bin/learn-omarchy "$(BIN_DIR)/learn-omarchy"
	install -m 755 bin/learn-omarchy-validate "$(BIN_DIR)/learn-omarchy-validate"
	install -m 644 share/applications/learn-omarchy.desktop "$(DESKTOP_DIR)/learn-omarchy.desktop"

uninstall:
	rm -f "$(BIN_DIR)/hexon-lab"
	rm -f "$(BIN_DIR)/learn-omarchy" "$(BIN_DIR)/learn-omarchy-validate"
	rm -f "$(DESKTOP_DIR)/learn-omarchy.desktop"
	rm -rf "$(APP_DIR)"
