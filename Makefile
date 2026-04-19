.PHONY: build install clean verify

build:
	swift build -c release

install: build
	cp .build/release/axon /usr/local/bin/axon

clean:
	swift package clean
	$(MAKE) -C Samples/AxonSample clean

# Full local check: builds axon + sample, runs all three test tiers.
# E2E steals focus — only run locally, never in CI or background agents.
verify: build
	$(MAKE) -C Samples/AxonSample build
	swift test --filter AxonUnitTests
	swift test --filter AxonIntegrationTests
	swift test --filter AxonE2ETests
