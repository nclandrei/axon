.PHONY: build install clean

build:
	swift build -c release

install: build
	cp .build/release/axon /usr/local/bin/axon

clean:
	swift package clean
