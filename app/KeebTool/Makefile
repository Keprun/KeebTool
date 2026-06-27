APP       = KeebTool.app
BIN       = .build/release/KeebTool
PLIST     = Info.plist

.PHONY: all build app run clean

all: app

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(PLIST) $(APP)/Contents/Info.plist
	cp $(BIN) $(APP)/Contents/MacOS/KeebTool
	codesign --force --sign - $(APP) 2>/dev/null || true
	@echo "built: $(APP)"

run: app
	open $(APP)

clean:
	swift package clean
	rm -rf $(APP) .build
