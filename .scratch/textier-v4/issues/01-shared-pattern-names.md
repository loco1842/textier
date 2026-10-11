# 01: Shared Pattern names

**What to build:** Several Patterns can share a name and behave as one group. A float and an integer Pattern both named `numeric` show as one `numeric` tab (or list section) in one color, and each Match keeps the Actions of the Pattern that found it, in the Inspector, in Match Windows and on a click in the Input. Today four places look a Pattern up by name and take the first; a Match now records its Pattern instead. A name's color is its first Pattern's (its `color`, or its palette default), and User Patterns are given palette colors per name. The names `json` and `escaped-json` are kept for the Built-in Patterns: a User Pattern or Preset with either name is skipped with a warning. Overlaps stay as they are: longest wins, then Config order, whatever the names.

Spec: `.scratch/textier-v4/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Two Patterns named `numeric` (`\b\d+\.\d+\b` with `copy`, `\b\d+\b` with `copy` and `open`) give one `numeric` tab with both kinds of Match, in one color
- [x] `3.14` is one `numeric` Match; `42` is another
- [x] A Match Window opened on an integer Match offers that Pattern's Actions, not the float Pattern's, and keeps them across a config reload
- [x] A regex Pattern named `json` is skipped with a warning naming the reserved name
- [x] Unit tests on `detect`/`inspect` cover one color per name, per-Pattern Actions and longest-wins across same-name Patterns; config tests cover the reserved names
- [x] App tests cover the shared tab and the Match Window's Actions

## Comments

**2026-10-09, closed without the manual pass:** Implemented and committed on master (v4 commits 5e60b94..60ba734); the full suite passes and the acceptance criteria are covered by `Tests/TextierCoreTests` and `Tests/TextierAppTests`. The user closed it without running `.scratch/textier-v4/manual-test.txt`, which is kept for whenever the SwiftUI controls, menu bar and layout get a look by hand.
