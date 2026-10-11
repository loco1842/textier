#!/usr/bin/env bash
# Assembles build/Textier.app, a menu bar agent (no Dock icon), from the SwiftPM binary.
# TEXTIER_VERSION and TEXTIER_BUILD set its version (0.1.0 and 1 by default);
# TEXTIER_UNIVERSAL=1 builds for Apple silicon and Intel both, as releases do.
set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/xcode-env.sh

version="${TEXTIER_VERSION:-0.1.0}"
build_number="${TEXTIER_BUILD:-1}"
arch_flags=()
if [[ "${TEXTIER_UNIVERSAL:-0}" == 1 ]]; then
    arch_flags=(--arch arm64 --arch x86_64)
fi

# macOS's bash 3.2 calls an empty array unbound under `set -u`, hence the `+`.
swift build -c release --product Textier ${arch_flags[@]+"${arch_flags[@]}"}
bin_dir="$(swift build -c release --show-bin-path ${arch_flags[@]+"${arch_flags[@]}"})"

app="build/Textier.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/Textier" "$app/Contents/MacOS/Textier"
# The bundled Grok Definitions come from logstash-patterns-core (Apache-2.0).
mkdir -p "$app/Contents/Resources"
cp NOTICE-logstash-patterns-core.txt "$app/Contents/Resources/"
# The app icon, drawn by scripts/make-app-icon.sh.
cp Resources/AppIcon.icns "$app/Contents/Resources/"

# Package.swift's platforms (.macOS(.v26)): an older macOS would let the app
# launch only for dyld to refuse the binary.
min_os="26.0"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Textier</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.textier.Textier</string>
    <key>CFBundleName</key>
    <string>textier</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
    <key>LSMinimumSystemVersion</key>
    <string>$min_os</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# The linker signs only the bare binary; seal the whole bundle (Info.plist included) ad hoc.
codesign --force --sign - "$app"

echo "Built $app"
