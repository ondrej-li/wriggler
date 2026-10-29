#!/usr/bin/env bash
# Uploads the exported .ipa to TestFlight.
#
# Needs an App Store Connect API key with the App Manager role. Provide the
# credentials through the environment:
#
#   APP_CONNECT_KEY_ID      the key's identifier, e.g. 2X9ABCDEFG
#   APP_CONNECT_ISSUER_ID   the issuer UUID from App Store Connect
#   APP_CONNECT_KEY_PATH    path to the downloaded AuthKey_<id>.p8
#
# See docs/TESTFLIGHT.md.
set -euo pipefail

IPA_DIR="${1:-build/export}"

: "${APP_CONNECT_KEY_ID:?set APP_CONNECT_KEY_ID}"
: "${APP_CONNECT_ISSUER_ID:?set APP_CONNECT_ISSUER_ID}"
: "${APP_CONNECT_KEY_PATH:?set APP_CONNECT_KEY_PATH}"

shopt -s nullglob
ipas=("$IPA_DIR"/*.ipa)
if [[ ${#ipas[@]} -eq 0 ]]; then
	echo "error: no .ipa in $IPA_DIR - run 'make archive' first" >&2
	exit 1
fi
if [[ ${#ipas[@]} -gt 1 ]]; then
	echo "error: more than one .ipa in $IPA_DIR" >&2
	exit 1
fi

echo "uploading ${ipas[0]}"
xcrun altool --upload-app \
	--type ios \
	--file "${ipas[0]}" \
	--apiKey "$APP_CONNECT_KEY_ID" \
	--apiIssuer "$APP_CONNECT_ISSUER_ID" \
	--apiKeyPath "$(dirname "$APP_CONNECT_KEY_PATH")"
