# 02: Borderless frosted Panel and header

**What to build:** The deployment target moves to macOS 26. The Panel becomes a borderless floating panel with no title bar or traffic lights, a frosted material background that follows light and dark (opaque under Reduce Transparency), and corners close to 26 pt. It stays floating, centered on open, and resizable from its edges. It remembers its size and the Input/Inspector divider position, and Esc still closes it. A 52 pt header strip drags the window and holds:
- the Highlighting toggle and the Tabs/List control as glass icon buttons (⌘E and ⌘L unchanged);
- a flexible space;
- the color-bar summary, one segment per Pattern sized by its Match count, with "N Patterns · M Matches" (shown only when the Inspector is);
- a "⚠ N" warnings badge, shown only when there are warnings, that opens a popover listing every warning.

The warnings footer and the Panel-level dividers go, and the Input/Inspector divider becomes invisible but stays draggable. The Inspector's own look is ticket 04.

Spec: `.scratch/textier-v5/spec.md` (stories 1–17; Implementation Decisions: Platform, Glass only on controls, Panel window, Header contents, No dividers). Visual reference: mockup variant E. Vocabulary: `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The package targets macOS 26 and builds
- [ ] The Panel shows no title bar or traffic lights, has a frosted background in both appearances, and is opaque with Reduce Transparency on
- [ ] Dragging the header moves the Panel; edges resize it; size and divider position are restored on the next open
- [ ] Esc closes the Panel and the global shortcut opens it with the Input focused
- [ ] The header's glass buttons toggle Highlighting and the layout; ⌘E and ⌘L still do
- [ ] The color bar and "N Patterns · M Matches" reflect the Input; they hide with the Inspector
- [ ] With warnings, the badge shows the count and its popover lists them all; with none, there's no badge and no footer
- [ ] App tests in `PanelTests`: the Panel becomes key with the Input focused, Esc closes it, size and divider are restored; existing app tests pass unchanged (tests that read the footer move to the warnings model)
