# 07: Settings: the Pattern test box

**What to build:** Under the Pattern editor's regex, a test box starts with the Panel's current Input and highlights the draft Pattern's Matches as the regex is typed, before anything is saved. Selecting a Match in it shows that Match's Fields. A regex that doesn't compile shows its error and no Matches.

Spec: `.scratch/textier-v4/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 06 (Settings: Patterns list and editor), 03 (Fields)

**Status:** done

- [x] With the Monolog line captured, the test box opens holding it
- [x] Typing `develop\.\w+` highlights `develop.WARNING` without writing the file
- [x] A draft `(?<level>WARNING|ERROR)` lists the Match and, once selected, a `level` Field
- [x] An unfinished regex `(?<x` shows its error and no Matches
- [x] App tests cover the test box's Matches and Fields for a draft through `SettingsModel`

## Comments

**2026-10-09, closed without the manual pass:** Implemented and committed on master (v4 commits 5e60b94..60ba734); the full suite passes and the acceptance criteria are covered by `Tests/TextierCoreTests` and `Tests/TextierAppTests`. The user closed it without running `.scratch/textier-v4/manual-test.txt`, which is kept for whenever the SwiftUI controls, menu bar and layout get a look by hand.
