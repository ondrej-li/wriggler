# Xcode is required for the iOS SDK; fall back to the standard install path when
# `xcode-select` still points at the Command Line Tools.
PYTHON ?= python3
DEVICE ?= iPhone 18 Pro
DEVELOPER_DIR ?= $(shell xcode-select -p 2>/dev/null | grep -q "Xcode.app" && xcode-select -p || echo /Applications/Xcode.app/Contents/Developer)
export DEVELOPER_DIR

XCODEBUILD := xcodebuild -project Wriggler.xcodeproj -scheme Wriggler \
	-destination 'platform=iOS Simulator,name=$(DEVICE)' \
	-derivedDataPath build \
	CODE_SIGNING_ALLOWED=NO

generate:
	xcodegen generate

art:
	$(PYTHON) Scripts/generate_placeholder_art.py

# Reference extraction from the original game; writes to git-ignored Extracted/.
extract:
	$(PYTHON) Scripts/extract_tape.py
	$(PYTHON) Scripts/extract_map.py
	$(PYTHON) Scripts/extract_links.py

build: generate
	$(XCODEBUILD) build

test: generate
	$(XCODEBUILD) test

lint:
	swift format lint --recursive --strict Sources Tests

run: build
	./Scripts/run-simulator.sh "$(DEVICE)"

clean:
	rm -rf build Wriggler.xcodeproj

.PHONY: generate art extract build test lint run clean
