# 07: Match Window in the new style

**What to build:** A Match Window takes the Panel's frosted material, corners, card and Action bar. It keeps its traffic lights in a transparent, full-size title bar with the title text hidden. The window title stays set for the Window menu and VoiceOver. The header holds:
- a solid pill with the Pattern's Glyph, name and the entry's index;
- the Match's one-line preview;
- the Action bar without Pop Out.

The parsed card fills the rest, and there's no line under the header. Opening, cascading, closing and following config reloads behave as today.

Spec: `.scratch/textier-v5/spec.md` (stories 64–67; Implementation Decisions: Match Window). Visual reference: mockup variant E (Pop Out opens one). Vocabulary: `CONTEXT.md`.

**Blocked by:** 04 (Inset Inspector pane, pill tabs and Glyphs), 06 (Action bar and cards)

**Status:** ready-for-agent

- [ ] Pop Out opens a frosted Match Window with traffic lights and no visible title text
- [ ] The header shows the solid Glyph pill, the preview and the Actions without Pop Out
- [ ] The parsed view sits in the card; a JSON Match shows the JSON Viewer as in the Inspector
- [ ] Several windows still open and cascade; closing, minimising and config reloads work as before
- [ ] Existing Match Window app tests pass unchanged; one checks the window's model carries the Glyph and the Actions without Pop Out
