APP_NAME = DigitalShadow
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build run install uninstall clean test

build:
	swift build -c release

run:
	swift run

test:
	swift test

app-bundle: build
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	sed -i '' 's/CFBundleVersion.*1/CFBundleVersion<string>$(shell date +%s)</string>/' $(APP_BUNDLE)/Contents/Info.plist

install: app-bundle
	cp -R $(APP_BUNDLE) /Applications/
	cp Resources/com.digitalshadow.daemon.plist ~/Library/LaunchAgents/
	launchctl load ~/Library/LaunchAgents/com.digitalshadow.daemon.plist

uninstall:
	launchctl unload ~/Library/LaunchAgents/com.digitalshadow.daemon.plist || true
	rm -f ~/Library/LaunchAgents/com.digitalshadow.daemon.plist
	rm -rf /Applications/$(APP_NAME).app

clean:
	swift package clean
	rm -rf $(BUILD_DIR)/*.app
