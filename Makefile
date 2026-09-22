PREFIX ?= /usr/local
DESTDIR ?=
APP_DIR := $(DESTDIR)$(PREFIX)/share/learn-omarchy
BIN_DIR := $(DESTDIR)$(PREFIX)/bin
DESKTOP_DIR := $(DESTDIR)$(PREFIX)/share/applications
ICON_DIR := $(DESTDIR)$(PREFIX)/share/icons/hicolor/256x256/apps
LICENSE_DIR := $(DESTDIR)$(PREFIX)/share/licenses/learn-omarchy
USER_DESKTOP_DIR := $(HOME)/.local/share/applications
USER_ICON_DIR := $(HOME)/.local/share/icons/hicolor/256x256/apps

.PHONY: check test install uninstall dev-launcher dev-launcher-remove

check:
	npm run check

test:
	npm test

install:
	install -d "$(APP_DIR)" "$(APP_DIR)/bin" "$(APP_DIR)/assets/arcade" "$(APP_DIR)/assets/characters" "$(APP_DIR)/assets/sounds" "$(BIN_DIR)" "$(DESKTOP_DIR)" "$(ICON_DIR)"
	install -m 644 share/icons/hicolor/256x256/apps/learn-omarchy.png "$(ICON_DIR)/learn-omarchy.png"
	cp -R app courses integrations src package.json character-lab.qml "$(APP_DIR)/"
	install -d "$(APP_DIR)/tools" "$(APP_DIR)/experiments/hexon-lab" "$(APP_DIR)/docs"
	install -m 644 experiments/hexon-lab/shell.qml experiments/hexon-lab/qmldir "$(APP_DIR)/experiments/hexon-lab/"
	install -m 644 tools/character-packs.ts tools/validate-course.ts tools/capture-practice.mjs tools/verify-window-owner.mjs "$(APP_DIR)/tools/"
	install -m 644 tools/validate-course-audio.ts tools/audio-coverage.ts tools/audio-production.ts "$(APP_DIR)/tools/"
	install -m 644 tools/play-timed-speech.mjs "$(APP_DIR)/tools/"
	install -m 644 tools/tutorial-launch.mjs "$(APP_DIR)/tools/"
	install -m 644 tools/install-geometry-provider.mjs "$(APP_DIR)/tools/"
	install -m 644 tools/bar-geometry.mjs "$(APP_DIR)/tools/"
	install -m 644 tools/generate-interaction-sounds.mjs "$(APP_DIR)/tools/"
	install -m 644 tools/prepare-intro-pixels.mjs "$(APP_DIR)/tools/"
	install -m 644 tools/prepare-splash-poster.mjs "$(APP_DIR)/tools/"
	install -m 644 docs/presentation.md "$(APP_DIR)/docs/"
	install -m 644 tools/generate-cheat-sheet.mjs "$(APP_DIR)/tools/"
	install -m 644 docs/curriculum-expansion.md "$(APP_DIR)/docs/"
	install -m 644 docs/character-packs.md docs/character-intros.md "$(APP_DIR)/docs/"
	install -m 644 assets/arcade/rescue-planet.png assets/arcade/rescue-ship.png "$(APP_DIR)/assets/arcade/"
	cp -R assets/sounds "$(APP_DIR)/assets/"
	install -d "$(APP_DIR)/assets/splash"
	install -m 644 assets/splash/learn-omarchy.png "$(APP_DIR)/assets/splash/learn-omarchy.png"
	install -m 644 assets/splash/provenance.json "$(APP_DIR)/assets/splash/provenance.json"
	install -m 644 assets/splash/learn-omarchy-poster.png assets/splash/poster.provenance.json "$(APP_DIR)/assets/splash/"
	node --experimental-strip-types tools/install-character-packs.ts assets/characters "$(APP_DIR)/assets/characters"
	install -m 755 bin/hexon-lab "$(BIN_DIR)/hexon-lab"
	install -m 755 bin/learn-omarchy "$(BIN_DIR)/learn-omarchy"
	install -m 755 bin/learn-omarchy-practice "$(APP_DIR)/bin/learn-omarchy-practice"
	install -m 755 bin/learn-omarchy-validate "$(BIN_DIR)/learn-omarchy-validate"
	install -m 644 share/applications/learn-omarchy.desktop "$(DESKTOP_DIR)/learn-omarchy.desktop"
	@if test -f LICENSE; then install -d "$(LICENSE_DIR)"; install -m 644 LICENSE "$(LICENSE_DIR)/"; install -m 644 LICENSE "$(APP_DIR)/"; fi
	@if test -f LICENSE-ASSETS.md; then install -d "$(LICENSE_DIR)"; install -m 644 LICENSE-ASSETS.md "$(LICENSE_DIR)/"; install -m 644 LICENSE-ASSETS.md "$(APP_DIR)/"; fi
	@if test -d LICENSES; then install -d "$(LICENSE_DIR)"; cp -R LICENSES "$(LICENSE_DIR)/"; cp -R LICENSES "$(APP_DIR)/"; fi

uninstall:
	rm -f "$(BIN_DIR)/hexon-lab"
	rm -f "$(BIN_DIR)/learn-omarchy" "$(BIN_DIR)/learn-omarchy-validate"
	rm -f "$(DESKTOP_DIR)/learn-omarchy.desktop"
	rm -f "$(ICON_DIR)/learn-omarchy.png"
	rm -rf "$(APP_DIR)"
	rm -rf "$(LICENSE_DIR)"

# Register this checkout in the current user's app menu without copying it:
# the entry runs bin/learn-omarchy from the repository, so edits apply directly.
dev-launcher:
	install -d "$(USER_DESKTOP_DIR)" "$(USER_ICON_DIR)"
	install -m 644 share/icons/hicolor/256x256/apps/learn-omarchy.png "$(USER_ICON_DIR)/learn-omarchy.png"
	sed -e 's|^Exec=.*|Exec=$(CURDIR)/bin/learn-omarchy|' -e 's|^Name=Learn Omarchy$$|Name=Learn Omarchy Local|' share/applications/learn-omarchy.desktop > "$(USER_DESKTOP_DIR)/learn-omarchy-local.desktop"
	rm -f "$(USER_DESKTOP_DIR)/learn-omarchy.desktop"
	-update-desktop-database "$(USER_DESKTOP_DIR)" 2>/dev/null
	@echo "Installed launcher: $(USER_DESKTOP_DIR)/learn-omarchy-local.desktop -> $(CURDIR)/bin/learn-omarchy"

dev-launcher-remove:
	rm -f "$(USER_DESKTOP_DIR)/learn-omarchy-local.desktop" "$(USER_DESKTOP_DIR)/learn-omarchy.desktop" "$(USER_ICON_DIR)/learn-omarchy.png"
	-update-desktop-database "$(USER_DESKTOP_DIR)" 2>/dev/null
