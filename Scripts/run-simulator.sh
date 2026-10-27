#!/usr/bin/env bash
# Installs and launches Wriggler on a named iOS simulator, booting it if needed.
set -euo pipefail

DEVICE="${1:-iPhone 18 Pro}"
BUNDLE_ID="cz.ondrejli.wriggler"
APP="build/Build/Products/Debug-iphonesimulator/Wriggler.app"

if [[ ! -d "$APP" ]]; then
	echo "error: $APP not found. Run 'make build' first." >&2
	exit 1
fi

UDID=$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 \
	| sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')

if [[ -z "$UDID" ]]; then
	echo "error: no simulator named '$DEVICE'." >&2
	xcrun simctl list devices available | sed -n '1,20p' >&2
	exit 1
fi

open -a Simulator
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" "${@:2}"
