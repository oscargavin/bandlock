APP_NAME = bandlock
BUNDLE = $(APP_NAME).app
BUILD_DIR = build
INSTALL_DIR = /Applications
LAUNCHAGENT_DIR = $(HOME)/Library/LaunchAgents
LAUNCHAGENT_LABEL = dev.bandlock.app
LAUNCHAGENT_PLIST = $(LAUNCHAGENT_DIR)/$(LAUNCHAGENT_LABEL).plist

.PHONY: build sign install uninstall clean

build:
	@echo "Building $(APP_NAME)..."
	@mkdir -p $(BUILD_DIR)/$(BUNDLE)/Contents/MacOS
	@cp Resources/Info.plist $(BUILD_DIR)/$(BUNDLE)/Contents/
	@swiftc Sources/bandlock.swift \
		-framework Cocoa \
		-framework CoreWLAN \
		-framework CoreLocation \
		-o $(BUILD_DIR)/$(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@echo "Built $(BUILD_DIR)/$(BUNDLE)"

sign: build
	@echo "Signing (ad-hoc)..."
	@codesign --force --deep -s - $(BUILD_DIR)/$(BUNDLE)
	@echo "Signed."

install: sign
	@echo "Installing to $(INSTALL_DIR)/$(BUNDLE)..."
	@rm -rf $(INSTALL_DIR)/$(BUNDLE)
	@cp -R $(BUILD_DIR)/$(BUNDLE) $(INSTALL_DIR)/$(BUNDLE)
	@echo "Creating LaunchAgent..."
	@mkdir -p $(LAUNCHAGENT_DIR)
	@cp Resources/dev.bandlock.app.plist $(LAUNCHAGENT_PLIST)
	@echo "Loading LaunchAgent..."
	@launchctl bootout gui/$$(id -u) $(LAUNCHAGENT_PLIST) 2>/dev/null || true
	@launchctl bootstrap gui/$$(id -u) $(LAUNCHAGENT_PLIST)
	@echo ""
	@echo "Installed! Run 'bandlock setup' to configure, then 'bandlock' to connect."
	@echo "The agent will auto-run at login."

uninstall:
	@echo "Uninstalling..."
	@launchctl bootout gui/$$(id -u) $(LAUNCHAGENT_PLIST) 2>/dev/null || true
	@rm -f $(LAUNCHAGENT_PLIST)
	@rm -rf $(INSTALL_DIR)/$(BUNDLE)
	@echo "Removed $(BUNDLE) and LaunchAgent."
	@echo "Config at ~/.config/bandlock/ was kept (delete manually if needed)."

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned."
