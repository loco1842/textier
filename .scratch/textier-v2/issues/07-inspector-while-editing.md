# 07: Inspector while editing

**What to build:** The Inspector stays steady while the Input changes. `inspect` with `previous` keeps the existing tabs in their order, appends tabs for newly matched Patterns before Plain Text, drops tabs that became empty, and moves the selection to the Match of the same Pattern whose range is nearest the old selection (falling back to the largest top-level Match when that tab is gone). The tab order is computed fresh when the Input is captured or pasted wholesale. The Inspector re-runs on the debounced edit cadence and after config reloads.

Spec: `.scratch/textier-v2/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Panel and Inspector skeleton)

**Status:** done

- [x] Typing a URL before the datetime on the Monolog line adds a url tab at the end instead of reordering tabs
- [x] Deleting the only datetime removes its tab; the selection falls back to the JSON
- [x] Editing inside the selected file path keeps a file path entry selected
- [x] A new capture orders tabs fresh by first appearance
- [x] Disabling a Pattern in the config removes its tab after save
- [x] Unit tests on the Inspection seam cover kept order, appended tabs, dropped tabs, nearest-selection and fallback

## Comments

**2026-10-09, implementation:** Built and committed; unit tests pass. "Nearest" follows the spec literally: deleting a Match before the selected one can move the selection to the Match that slid into the old range. A paste that replaces the whole Input orders tabs afresh, like a capture.
- Automated: the matching suites in `Tests/TextierAppTests` cover the acceptance criteria in-process. Nothing left to check by hand.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
