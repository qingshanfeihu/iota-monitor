APP_NAME = IOTA Monitor
BUNDLE_ID = com.jyz.iota-monitor
BIN = .build/release/IotaMonitor
APP = $(APP_NAME).app

.PHONY: build test app install run clean

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

clean:
	swift package clean
	@rm -rf "$(APP)"
