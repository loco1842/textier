# Sourced by the other scripts. The Command Line Tools lack the macro plugins
# SwiftUI (`@State`) and Swift Testing (`#expect`) need, so build with an
# installed Xcode while xcode-select still points at the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
    for xcode in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [[ -d "$xcode" ]]; then
            export DEVELOPER_DIR="$xcode/Contents/Developer"
            break
        fi
    done
fi
