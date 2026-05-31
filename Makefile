APP_NAME   := Camera Viewer
SCHEME     := CameraViewer
BUILD_DIR  := $(shell xcodebuild -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | awk '$$1 == "BUILT_PRODUCTS_DIR" {print $$3}')
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_TO := /Applications/$(APP_NAME).app

.PHONY: build install uninstall clean release release-unsigned

build:
	xcodebuild -scheme $(SCHEME) -configuration Release build

# Signed + notarized DMG. Requires DEVELOPER_ID, TEAM_ID, NOTARY_PROFILE (see scripts/release.sh).
release:
	scripts/release.sh

# Build the DMG without signing/notarizing — for local inspection of the pipeline.
release-unsigned:
	SKIP_SIGNING=1 scripts/release.sh

install: build
	rm -rf "$(INSTALL_TO)"
	cp -R "$(APP_BUNDLE)" "$(INSTALL_TO)"
	xattr -dr com.apple.quarantine "$(INSTALL_TO)" 2>/dev/null || true
	@echo "Installed to $(INSTALL_TO)"
	@echo "Launch from Spotlight or: open \"$(INSTALL_TO)\""

uninstall:
	rm -rf "$(INSTALL_TO)"
	@echo "Removed $(INSTALL_TO)"

clean:
	xcodebuild -scheme $(SCHEME) clean
