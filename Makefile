APP_NAME = IOTA Monitor
BUNDLE_ID = com.jyz.iota-monitor
BIN = .build/release/IotaMonitor
APP = $(APP_NAME).app
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo v0.0.0)
DMG = IOTA-Monitor-$(VERSION)-arm64.dmg

.PHONY: build test app install run restart clean dmg

build:
	swift build -c release

test:
	swift run SelfTest

app: build
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS"
	@cp $(BIN) "$(APP)/Contents/MacOS/IotaMonitor"
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0">\n\
<dict>\n\
	<key>CFBundleExecutable</key><string>IotaMonitor</string>\n\
	<key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>\n\
	<key>CFBundleName</key><string>$(APP_NAME)</string>\n\
	<key>CFBundleDisplayName</key><string>$(APP_NAME)</string>\n\
	<key>CFBundlePackageType</key><string>APPL</string>\n\
	<key>CFBundleShortVersionString</key><string>1.0</string>\n\
	<key>CFBundleVersion</key><string>1</string>\n\
	<key>LSMinimumSystemVersion</key><string>13.0</string>\n\
	<key>LSUIElement</key><true/>\n\
	<key>NSHighResolutionCapable</key><true/>\n\
	<key>NSPrincipalClass</key><string>NSApplication</string>\n\
</dict>\n\
</plist>\n' > "$(APP)/Contents/Info.plist"
	@echo "打包完成: $(APP)"

install: app
	@rm -rf "/Applications/$(APP)"
	@cp -R "$(APP)" /Applications/
	@echo "已安装到 /Applications/$(APP)"

run:
	swift run IotaMonitor

# 只重启本监控 App。必须用完整精确路径匹配，
# 绝不能用 "/Applications/IOTA" 这种宽前缀（会误杀 IOTA Train at Home.app）。
restart:
	-pkill -f "IOTA Monitor.app/Contents/MacOS/IotaMonitor"
	sleep 1
	open "/Applications/IOTA Monitor.app"

# 打 DMG 安装包：ad-hoc 自签名（免开发者账号；arm64 必需）+ Applications 拖拽目录
dmg: app
	@codesign --force --sign - "$(APP)"
	@rm -rf /tmp/dmgroot-$(VERSION) && mkdir -p /tmp/dmgroot-$(VERSION)
	@cp -R "$(APP)" /tmp/dmgroot-$(VERSION)/
	@ln -s /Applications /tmp/dmgroot-$(VERSION)/Applications
	@rm -f "$(DMG)"
	@hdiutil create -volname "IOTA Monitor" -srcfolder /tmp/dmgroot-$(VERSION) -ov -format UDZO "$(DMG)" >/dev/null
	@hdiutil verify "$(DMG)" 2>&1 | tail -1
	@echo "DMG 打包完成: $(DMG)"

clean:
	swift package clean
	@rm -rf "$(APP)" "$(DMG)"
