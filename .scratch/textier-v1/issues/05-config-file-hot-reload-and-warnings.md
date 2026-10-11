# 05: Config file with hot reload and warnings

**What to build:** Patterns, the shortcut and (an empty) editor command live in `~/.config/textier/config.json`. On first launch, when the file is absent, textier writes it with every Preset (URL, datetime, file path on; log level off), the Built-in `json` entry enabled, the default shortcut ⌃⌥T and an empty `editorCommand`, so the file documents itself. Each Pattern entry has `name`, `enabled`, `actions` (ordered; first is the default Action), optional `color`, and either `regex` or a built-in id. User Patterns are plain regex entries the user adds. Loading returns a Config plus warnings: a Pattern with an invalid regex or an unknown Action is dropped with a warning naming the Pattern and the problem, the rest loads; malformed JSON yields one fatal warning and the previously loaded Config stays active. textier watches the file and reloads on save; a Reload Config menu item triggers the same path. The global shortcut is registered from Config and re-registered on reload. Warnings appear as a one-line footer in the Panel and as a badge on the menu bar icon while any exist.

Spec: `.scratch/textier-v1/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 02 (Global shortcut), 03 (Presets and overlap/nesting rules)

**Status:** done

- [x] First launch with no config file writes one containing all Presets, the `json` Built-in, the shortcut and an empty `editorCommand`; loading that file back yields an identical Config
- [x] Adding a User Pattern (e.g. a namespaced PHP class regex) and saving highlights it in the Panel without restarting textier
- [x] Setting `enabled: false` on `json` stops JSON detection after save
- [x] Changing the shortcut in the file re-registers it after save
- [x] A Pattern with an invalid regex is skipped; all others still highlight; the Panel footer and menu bar badge show the warning
- [x] A Pattern with an unknown Action name is skipped with a warning
- [x] Malformed JSON in the file keeps the last good Config active and shows a fatal warning
- [x] Reload Config menu item reloads the file
- [x] Unit tests on the config seam cover default emission round trip, bad regex skip, unknown Action skip, malformed JSON rejection

## Comments

**2026-10-08, implementation:** Built and committed.

- **Config file format** (`ConfigFile` in `TextierCore`). Top-level keys are written in this order: `shortcut`, `editorCommand`, `patterns`. Pattern order in the file is Config order. Each entry is written as `name`, then exactly one of `regex` or `builtin` (a `BuiltinPattern` raw value: `json`, `escaped-json`), then `enabled` (defaults to `true` when missing), `actions` (Action raw values; the first is the default Action) and an optional `color`. Unknown keys are ignored. The emitted file leaves `/` unescaped, so URL regexes stay readable. Backslashes are JSON-escaped, so a regex `\b` is written `"\\b"`.
- **Shortcut string format** (`Shortcut` in `TextierCore`). Modifiers and one key are joined by `+`, for example `"ctrl+option+t"`, which is the default.
  - Modifiers: `ctrl`/`control`, `option`/`opt`/`alt`, `shift`, `cmd`/`command`. At least one of ctrl, option or cmd is required.
  - Keys: `a`–`z`, `0`–`9`, `f1`–`f12`, `space`.
  - Case and spaces around `+` are ignored.
  - textier writes modifiers in macOS order (⌃⌥⇧⌘).
- **Loading.** A Pattern is dropped with a warning naming it and the problem when it has: an invalid regex, an unknown Action or Built-in id, no name, both or neither of `regex`/`builtin`, no `actions` list, or a wrongly typed `enabled`/`color`. The rest of the file loads.
  - An invalid `shortcut` gives a warning, and ⌃⌥T is used.
  - An empty or missing `editorCommand` loads as unset (`nil`).
  - Invalid JSON, a top level that isn't an object, or a missing `patterns` array gives one fatal warning and no Config. The app keeps the last good Config.
- **App.**
  - `AppConfig.store` (an `@Observable` `ConfigStore`) writes the defaults on first launch, loads the file and watches it. It watches both the file and its directory, so editors' atomic rename-saves are caught, and re-arms the file watch after each change; reloads are debounced by 200 ms.
  - Reload Config in the menu runs the same path. Each reload re-registers the hotkey if the shortcut changed, re-detects the Panel's Input and refreshes the footer and the badge.
  - If a new shortcut can't be registered, the previous one is put back and a warning says so.
  - The badge swaps the menu bar icon for `exclamationmark.triangle.fill` while warnings exist. The menu also lists the warnings.
  - `TEXTIER_CONFIG=/some/path.json` overrides the file location, for trying configs out without touching `~/.config`.
- **Verified** with the debug binary and `TEXTIER_CONFIG` pointing at a scratch file:
  - first launch wrote the full default file and loaded it with 0 warnings
  - an atomic save (write a temporary file, then `mv`) with a broken regex reloaded with one warning naming it
  - a later in-place write reloaded too (6 patterns)
  - truncated JSON reloaded with one fatal warning and kept 6 patterns
  - 52 tests pass (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`)
- **Still to check by hand** (needs the UI):
  - a saved User Pattern highlights in the Panel without a restart; the reload itself is verified
  - `json` with `enabled: false` stops JSON highlighting; this needs ticket 04's scanner, and loading the flag is unit-tested
  - changing the shortcut in the file makes the new one work and the old one stop
  - the Panel footer and the menu bar badge appear and clear with warnings
  - the Reload Config menu item

**2026-10-08, follow-up (code review):** Per-Pattern `color` now does something. `#RRGGBB` or `#RRGGBBAA` (any case) tints that Pattern's highlight (background at 0.18 alpha unless the color carries its own alpha; underline in the color); anything else, including a non-string, warns naming the Pattern and loads it without a color instead of skipping it. `Match.color` carries the Pattern's color, children included. Unit tests cover valid and invalid colors through `ConfigFile.load` and color propagation through `detect`. The footer and badge also show a new runtime warning slot, `ConfigStore.editorWarning` (see ticket 06). Check by hand: add `"color": "#e5c07b"` to the `json` entry, save, and see the payload highlighted in that color; set `"color": "orange"` and see the warning.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v1/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
