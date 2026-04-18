APP_NAME   := CameraViewer
SCHEME     := CameraViewer
BUILD_DIR  := $(shell xcodebuild -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | awk '$$1 == "BUILT_PRODUCTS_DIR" {print $$3}')
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_TO := /Applications/$(APP_NAME).app

.PHONY: build install uninstall clean bootstrap

bootstrap:
	scripts/bootstrap.sh

build: bootstrap
	xcodebuild -scheme $(SCHEME) -configuration Release build

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
