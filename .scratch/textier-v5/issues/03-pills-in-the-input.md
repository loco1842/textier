# 03: Pills in the Input

**What to build:** Each top-level Match in the Input is drawn as a rounded pill in its Pattern's tint, with the Match's text in the Pattern's text color and no underline. A Match that wraps gets a rounded pill piece on each line. Hovering a pill deepens it to the strong tint. The entry selected in the Inspector shows in the Input with the strong tint and a 1.5 pt ring in the solid color, and for a nested Match this happens inside its parent's pill. With Highlighting off nothing is drawn. Click to copy and double-click to inspect behave as they do today. An empty Input shows a faint "Paste or type text — ⌘V" placeholder.

Spec: `.scratch/textier-v5/spec.md` (stories 18–24; Implementation Decisions: Input highlighting, Empty state). Visual reference: mockup variant E. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Saturated palette and color roles)

**Status:** ready-for-agent

- [ ] Matches show as rounded tinted pills with colored text and no underline, in light and dark
- [ ] A Match wrapping over several lines has a rounded piece on each line
- [ ] Hover deepens a pill; the Inspector's selected entry gets the strong tint and a ring, and a selected nested Match gets them inside its parent
- [ ] Highlighting off removes the pills; click copies and double-click inspects as before
- [ ] An empty Input shows the placeholder, and typing hides it
- [ ] Existing `InputTests` pass unchanged; a test checks that the Inspector selection reaches the Input's highlighted range through the model
