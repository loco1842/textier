# 06: Settings: Patterns list and editor

**What to build:** The Patterns section lists every Pattern in priority order, each row with its name, its name's color and its regex, with a switch to turn it on or off, a filter, and drag to reorder. Selecting a row opens the editor: name, regex, Actions and color, with the compile step's error shown under the regex. User Patterns can be added and deleted; a Preset can be duplicated into a User Pattern, edited, and restored to its default while it differs from it; Built-in Patterns offer only on/off. Everything saves as in ticket 05.

Spec: `.scratch/textier-v4/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 05 (Settings window), 02 (Compile step and Perl-style regex), 01 (Shared Pattern names)

**Status:** done

- [x] Dragging `log level` above `url` writes the new order and changes which Pattern wins an overlap
- [x] Turning `log level` on writes `"enabled": true` and the Panel highlights levels
- [x] Typing `a\Kb` in the regex shows "\K isn't supported" and doesn't write the file; fixing it writes
- [x] Add, delete and Duplicate (from `url`) change the file as expected; Restore default appears only on a changed Preset and puts it back
- [x] The `json` Built-in Pattern's row has a switch but no editable regex
- [x] Two Patterns named `numeric` show the same color dot
- [x] App tests cover reorder, toggle, edit with an invalid regex, add, delete, duplicate and Restore default through `SettingsModel`

## Comments

**2026-10-09, closed without the manual pass:** Implemented and committed on master (v4 commits 5e60b94..60ba734); the full suite passes and the acceptance criteria are covered by `Tests/TextierCoreTests` and `Tests/TextierAppTests`. The user closed it without running `.scratch/textier-v4/manual-test.txt`, which is kept for whenever the SwiftUI controls, menu bar and layout get a look by hand.
