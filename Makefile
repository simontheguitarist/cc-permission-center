APP_NAME   := CCPermissionCenter
HOOK_NAME  := ccpc-hook
BUILD_DIR  := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONFIG     := release

.PHONY: all build app run clean

all: app

build:
	swift build -c $(CONFIG)

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp .build/$(CONFIG)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp .build/$(CONFIG)/$(HOOK_NAME) $(APP_BUNDLE)/Contents/Resources/$(HOOK_NAME)
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	codesign --force --deep --sign - $(APP_BUNDLE) >/dev/null 2>&1 || true
	@echo ""
	@echo "Built: $(APP_BUNDLE)"
	@echo "Run with: make run  (or: open $(APP_BUNDLE))"

run: app
	open $(APP_BUNDLE)

clean:
	rm -rf .build $(BUILD_DIR)
