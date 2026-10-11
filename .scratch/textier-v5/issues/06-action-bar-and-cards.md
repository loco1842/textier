# 06: Action bar and cards

**What to build:** The selected entry's first Action becomes a pill filled with the entry's solid color, with on-solid text and a "↩" hint. The other Actions are borderless pill buttons with an SF Symbol and a label (copy, a globe for Open in Browser, `</>` for Open in Editor, a wand for Copy Beautified, a pop-out mark for Pop Out). Plain Text keeps Copy only, and the bar stays hidden when nothing is selected.

The parsed view sits in a card with 10 pt corners, inset 8 pt at the bottom of the Inspector pane. The JSON Viewer's card is filled with the active VS Code theme's background and keeps its coloring (ADR-0003). URL, datetime, file path, Fields and text views sit in a neutral card, as label/value rows with faint lines between them inside the card and copy buttons that appear on hover. What every Action and view does is unchanged.

Spec: `.scratch/textier-v5/spec.md` (stories 52–57; Implementation Decisions: Action bar, Cards). Visual reference: mockup variant E. Vocabulary: `CONTEXT.md`.

**Blocked by:** 04 (Inset Inspector pane, pill tabs and Glyphs)

**Status:** ready-for-agent

- [ ] The primary Action is a solid pill in the Pattern's color with readable text and "↩"; the others are icon+label pills
- [ ] Return still runs the first Action, and every Action does what it did
- [ ] The JSON Viewer sits in a card with the theme's background, in light and dark themes
- [ ] The other parsed views sit in a neutral card with label/value rows; copy buttons show on hover and still copy
- [ ] `JSONViewerTests` and `InspectorTests` pass unchanged

## Comments

If this runs in the same wave as 05, this ticket owns the Action bar and the detail card; 05 owns the rows and section list.
