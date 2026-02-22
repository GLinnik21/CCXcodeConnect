APP_NAME = CCXcodeConnect
INSTALL_DIR = $(HOME)/Applications
SCHEME = CCXcodeConnect
BUILD_DIR = .build/xcode

.PHONY: build install uninstall clean build-cli run

build:
	xcodebuild -scheme $(SCHEME) -configuration Release -derivedDataPath $(BUILD_DIR) build

install: build
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$$(find $(BUILD_DIR) -name '$(APP_NAME).app' -path '*/Release/*' | head -1)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed $(APP_NAME).app to $(INSTALL_DIR)"
	@open "$(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	@osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null || true
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@rm -f $(HOME)/.claude/ide/*.lock
	@echo "Uninstalled $(APP_NAME)"

clean:
	@rm -rf $(BUILD_DIR)
	@swift package clean

build-cli:
	swift build -c release

run:
	swift run cc-xcode-connect
