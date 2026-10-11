# 02: Pattern colors

**What to build:** Each Pattern's Matches are tinted in that Pattern's own color, in the Input and as a dot on its Inspector tab. A built-in palette gives every Preset and Built-in a distinct default by name, and User Patterns without a color get the next unused palette color in Config order; an explicit `color` always wins. `color` accepts `"#RRGGBB"`, `"#RRGGBBAA"` or `{"light": "#…", "dark": "#…"}`; anything else warns and falls back to the palette. A Match carries its resolved light/dark color, and the Panel uses the one for the current appearance. First-launch emission writes the Presets' colors so the file documents itself. An existing config file without colors gets the palette with no edits.

Spec: `.scratch/textier-v2/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Panel and Inspector skeleton)

**Status:** done

- [x] On the Monolog line, datetime, json and the log level (when enabled) are tinted in distinct colors in the Input; tabs show matching color dots
- [x] An existing v1 config file with no `color` fields shows palette colors without being edited
- [x] A User Pattern with no color gets a palette color not used by any other Pattern
- [x] `"color": "#e5c07b"` and `{"light": …, "dark": …}` both apply; switching system appearance switches the pair
- [x] An invalid color warns in the footer and the Pattern uses its palette color
- [x] Unit tests on the detection and config seams cover palette defaults, User Pattern assignment, single and paired colors, invalid colors, and first-launch round trip

## Comments

**2026-10-09, implementation:** Built and committed; unit tests pass. Palette and resolution in `PatternColor.swift` (tests: `PatternColorTests.swift`, `ConfigFileTests.swift`). Shipped Presets and Built-ins carry their palette color, so first-launch emission writes them; a v1 file without colors resolves the same colors by name.
- Automated: the matching suites in `Tests/TextierAppTests` cover the acceptance criteria in-process. Still to check by hand: steps 1, 9 of `.scratch/textier-v2/manual-test.txt`.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
