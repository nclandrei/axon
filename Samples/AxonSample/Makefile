.PHONY: build clean

APP_NAME = AxonSample
APP_BUNDLE = .build/$(APP_NAME).app
BIN = .build/release/$(APP_NAME)

build:
	swift build -c release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BIN) $(APP_BUNDLE)/Contents/MacOS/
	cp Info.plist.template $(APP_BUNDLE)/Contents/Info.plist
	@echo "Built $(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
