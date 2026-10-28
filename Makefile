APP_NAME   = KeylightBar
BUNDLE_ID  = com.cedricscherer.keylightbar
APP_DIR    = $(APP_NAME).app
CONTENTS   = $(APP_DIR)/Contents
BIN        = $(CONTENTS)/MacOS/$(APP_NAME)
PLIST      = $(CONTENTS)/Info.plist
VERSION    = $(shell sed -n 's/^let appVersion = "\([^"]*\)".*/\1/p' main.swift)

.PHONY: all build bundle run clean

all: bundle

build:
	@mkdir -p $(CONTENTS)/MacOS
	swiftc main.swift -o $(BIN)

bundle: build
	@mkdir -p $(CONTENTS)
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n    <key>CFBundleName</key>\n    <string>$(APP_NAME)</string>\n    <key>CFBundleIdentifier</key>\n    <string>$(BUNDLE_ID)</string>\n    <key>CFBundleShortVersionString</key>\n    <string>$(VERSION)</string>\n    <key>CFBundleVersion</key>\n    <string>$(VERSION)</string>\n    <key>CFBundleExecutable</key>\n    <string>$(APP_NAME)</string>\n    <key>LSUIElement</key>\n    <true/>\n</dict>\n</plist>\n' > $(PLIST)
	@echo "$(APP_DIR) v$(VERSION) built."

run: bundle
	open $(APP_DIR)

clean:
	rm -rf $(APP_DIR) $(APP_NAME)
