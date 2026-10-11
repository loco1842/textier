#!/usr/bin/env bash
# Records the README demo: the DemoFrames app test captures textier's popover,
# Panel and Settings from the real app (it takes the screen for about 20 s; keep
# your hands off, and the display awake), then scripts/make-demo.swift assembles
# docs/demo/demo.mp4 and docs/demo/demo.gif. Needs Screen Recording for the terminal.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/xcode-env.sh

frames="$(mktemp -d)"
trap 'rm -rf "$frames"' EXIT

TEXTIER_DEMO_FRAMES="$frames" caffeinate -d -i scripts/test.sh --filter DemoFrames
swift scripts/make-demo.swift "$frames" docs/demo
ls -lh docs/demo
