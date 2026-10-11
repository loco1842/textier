# 04: Inset Inspector pane, pill tabs and Glyphs

**What to build:** Every Inspector tab carries a **Glyph**. The core decides it from the group's first Pattern: one Glyph per Built-in Pattern and per Preset, one shared by all User Patterns, and one for Plain Text. The first regex Pattern with a Preset's name is that Preset (`CONTEXT.md`). The app shows Glyphs as SF Symbols.

The Inspector becomes a pane inset 8 pt from the window's right and bottom edges, with 18 pt corners and a soft shadow. Its fill is the window's material one step lighter (darker in dark mode), with no second blur and no glass. The pane has no dividers: the list/detail split stays resizable with an invisible divider, and scroll edges fade.

Tabs become pills: tint at rest, with the Glyph, name and count in the text color. The selected tab is solid, with on-solid text and Glyph. Plain Text is a neutral grey pill. ⌘1…⌘9 still select tabs, and tabs scroll horizontally when they overflow. List-layout section headers show the disclosure, Glyph, name and a count chip.

The pane slides and fades in when the first Match appears, and a tab change animates with a short spring. None of it animates under Reduce Motion.

Spec: `.scratch/textier-v5/spec.md` (stories 25–32, 38–39, 48–51, 68–69; Implementation Decisions: Glyph, Layout geometry, Tabs, Motion). Visual reference: mockup variant E. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Saturated palette and color roles), 02 (Borderless frosted Panel and header)

**Status:** ready-for-agent

- [ ] Each Inspector tab has the right Glyph: the Built-in Patterns, each Preset, User Patterns, Plain Text
- [ ] Two regex Patterns named `url`, in either order, give the tab the url Glyph
- [ ] The Inspector is an inset, rounded, lighter pane with no visible dividers, and both splits can still be dragged
- [ ] Tabs are tinted pills with Glyph, name and count; the selected one is solid with readable text; Plain Text is grey
- [ ] ⌘1…⌘9, ⌘L and the List layout work as before, and section headers show Glyph and count chip
- [ ] The pane slides in on the first Match; tab changes spring; nothing animates with Reduce Motion
- [ ] Core tests in the style of `InspectionTests` cover the Glyph rules; `InspectorTests` and `ListLayoutTests` pass unchanged
