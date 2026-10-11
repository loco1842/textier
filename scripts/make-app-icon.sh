#!/usr/bin/env bash
# Draws the app icon (scripts/make-app-icon.swift) and packs it into
# Resources/AppIcon.icns, which bundle.sh puts in the app. Run it after changing
# the icon's drawing; the .icns is committed.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/xcode-env.sh

iconset="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-app-icon.swift "$iconset"
mkdir -p Resources
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
rm -rf "$(dirname "$iconset")"
echo "Wrote Resources/AppIcon.icns"
