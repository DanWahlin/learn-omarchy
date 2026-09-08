PREFIX ?= /usr/local
DESTDIR ?=
APP_DIR := $(DESTDIR)$(PREFIX)/share/learn-omarchy
BIN_DIR := $(DESTDIR)$(PREFIX)/bin
DESKTOP_DIR := $(DESTDIR)$(PREFIX)/share/applications
ICON_DIR := $(DESTDIR)$(PREFIX)/share/icons/hicolor/256x256/apps
USER_DESKTOP_DIR := $(HOME)/.local/share/applications
USER_ICON_DIR := $(HOME)/.local/share/icons/hicolor/256x256/apps

.PHONY: check test install uninstall dev-launcher dev-launcher-remove

check:
	npm run check

test:
	npm test

install:
	install -d "$(APP_DIR)" "$(APP_DIR)/bin" "$(APP_DIR)/assets/characters" "$(APP_DIR)/assets/sounds" "$(BIN_DIR)" "$(DESKTOP_DIR)" "$(ICON_DIR)"
	install -m 644 share/icons/hicolor/256x256/apps/learn-omarchy.png "$(ICON_DIR)/learn-omarchy.png"
	cp -R app courses integrations src package.json character-lab.qml "$(APP_DIR)/"
	install -d "$(APP_DIR)/tools" "$(APP_DIR)/experiments/hexon-lab" "$(APP_DIR)/docs"
	install -m 644 experiments/hexon-lab/shell.qml experiments/hexon-lab/qmldir "$(APP_DIR)/experiments/hexon-lab/"
	install -m 644 tools/character-packs.ts tools/validate-course.ts tools/capture-practice.mjs tools/verify-window-owner.mjs "$(APP_DIR)/tools/"
	install -m 644 tools/validate-course-audio.ts tools/audio-coverage.ts tools/audio-production.ts "$(APP_DIR)/tools/"
	install -m 644 docs/character-packs.md docs/character-intros.md "$(APP_DIR)/docs/"
	cp -R assets/sounds "$(APP_DIR)/assets/"
	install -d "$(APP_DIR)/assets/splash"
	install -m 644 assets/splash/learn-omarchy.png "$(APP_DIR)/assets/splash/learn-omarchy.png"
	install -m 644 assets/splash/provenance.json "$(APP_DIR)/assets/splash/provenance.json"
	node --experimental-strip-types tools/install-character-packs.ts assets/characters "$(APP_DIR)/assets/characters"
	install -m 755 bin/hexon-lab "$(BIN_DIR)/hexon-lab"
	install -m 755 bin/learn-omarchy "$(BIN_DIR)/learn-omarchy"
	install -m 755 bin/learn-omarchy-practice "$(APP_DIR)/bin/learn-omarchy-practice"
	install -m 755 bin/learn-omarchy-validate "$(BIN_DIR)/learn-omarchy-validate"
	install -m 644 share/applications/learn-omarchy.desktop "$(DESKTOP_DIR)/learn-omarchy.desktop"

uninstall:
	rm -f "$(BIN_DIR)/hexon-lab"
	rm -f "$(BIN_DIR)/learn-omarchy" "$(BIN_DIR)/learn-omarchy-validate"
	rm -f "$(DESKTOP_DIR)/learn-omarchy.desktop"
	rm -f "$(ICON_DIR)/learn-omarchy.png"
	rm -rf "$(APP_DIR)"

# Register this checkout in the current user's app menu without copying it:
# the entry runs bin/learn-omarchy from the repository, so edits apply directly.
dev-launcher:
	install -d "$(USER_DESKTOP_DIR)" "$(USER_ICON_DIR)"
	install -m 644 share/icons/hicolor/256x256/apps/learn-omarchy.png "$(USER_ICON_DIR)/learn-omarchy.png"
	sed 's|^Exec=.*|Exec=$(CURDIR)/bin/learn-omarchy|' share/applications/learn-omarchy.desktop > "$(USER_DESKTOP_DIR)/learn-omarchy.desktop"
	-update-desktop-database "$(USER_DESKTOP_DIR)" 2>/dev/null
	@echo "Installed launcher: $(USER_DESKTOP_DIR)/learn-omarchy.desktop -> $(CURDIR)/bin/learn-omarchy"

dev-launcher-remove:
	rm -f "$(USER_DESKTOP_DIR)/learn-omarchy.desktop" "$(USER_ICON_DIR)/learn-omarchy.png"
	-update-desktop-database "$(USER_DESKTOP_DIR)" 2>/dev/null
