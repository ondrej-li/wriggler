# Xcode is required for the iOS SDK; fall back to the standard install path when
# `xcode-select` still points at the Command Line Tools.
PYTHON ?= python3
DEVICE ?= iPhone 18 Pro
# Empty means "no team yet": simulator builds work, device builds ask Xcode.
# Set it once in your shell profile to keep it across regenerations.
DEVELOPMENT_TEAM ?=
export DEVELOPMENT_TEAM

# Optional local overrides (team ID, device name). Not committed.
-include local.mk
DEVELOPER_DIR ?= $(shell xcode-select -p 2>/dev/null | grep -q "Xcode.app" && xcode-select -p || echo /Applications/Xcode.app/Contents/Developer)
export DEVELOPER_DIR

BUNDLE_ID := cz.ondrejli.wriggler
XCODEBUILD := xcodebuild -project Wriggler.xcodeproj -scheme Wriggler \
	-destination 'platform=iOS Simulator,name=$(DEVICE)' \
	-derivedDataPath build \
	CODE_SIGNING_ALLOWED=NO

ARCHIVE := build/Wriggler.xcarchive
EXPORT_DIR := build/export

generate:
	xcodegen generate

# Opens the project in Xcode once it exists, so it can be run from the IDE.
open: generate
	open Wriggler.xcodeproj

build: generate
	$(XCODEBUILD) build

test: generate
	$(XCODEBUILD) test

lint:
	swift format lint --recursive --strict Sources Tests

run: build
	./Scripts/run-simulator.sh "$(DEVICE)"

# Signed archive for TestFlight. Needs a development team, which Xcode can also
# be given through the UI: `make archive DEVELOPMENT_TEAM=ABCDE12345`.
archive: generate
	xcodebuild -project Wriggler.xcodeproj -scheme Wriggler \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE) \
		-allowProvisioningUpdates \
		$(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM),) \
		$(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER),) \
		archive
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE) \
		-exportPath $(EXPORT_DIR) \
		-exportOptionsPlist Support/ExportOptions.plist \
		-allowProvisioningUpdates
	@echo "exported to $(EXPORT_DIR)"

# Uploads the exported build to TestFlight with an App Store Connect API key,
# see docs/TESTFLIGHT.md.
upload:
	./Scripts/upload-testflight.sh

# Builds and uploads in one step using the account signed in to Xcode, so no API
# key is needed. Handy locally; CI has no Xcode account and uses `make upload`.
upload-xcode: generate
	xcodebuild -project Wriggler.xcodeproj -scheme Wriggler \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE) \
		-allowProvisioningUpdates \
		$(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM),) \
		$(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER),) \
		archive
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE) \
		-exportOptionsPlist Support/ExportOptions-upload.plist \
		-allowProvisioningUpdates

art: icon

icon:
	$(PYTHON) Scripts/make_app_icon.py

# Rebuilds the maze data the game loads, from the map plus the curated links.
maze:
	$(PYTHON) Scripts/build_maze_data.py

# Reference extraction from the original game; writes to git-ignored Extracted/.
extract:
	$(PYTHON) Scripts/extract_tape.py
	$(PYTHON) Scripts/extract_map.py
	$(PYTHON) Scripts/extract_links.py

# Room-index labels burned onto the map; writes into resources/.
annotate-map: extract
	$(PYTHON) Scripts/annotate_map.py

clean:
	rm -rf build Wriggler.xcodeproj

.PHONY: generate open build test lint run archive upload upload-xcode art icon maze extract annotate-map clean
