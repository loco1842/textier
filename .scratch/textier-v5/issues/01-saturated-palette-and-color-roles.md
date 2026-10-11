# 01: Saturated palette and color roles

**What to build:** Patterns get the saturated Radix palette: amber for JSON, orange for escaped JSON, blue for URL, violet for datetime, green for file path, and red for log level. User Patterns without a color take pink, cyan, lime, purple or grey. A new pure function in the core library turns any Pattern color (one hex value or a light/dark pair from the config) into the roles the UI draws with, per appearance:
- **tint**: a pill or tab at rest;
- **strong tint**: hover, the selected Match, the selected row;
- **solid**: the selected tab, the primary Action, row bars, rings and the color bar;
- **text**: a Pattern's colored text, adjusted until it reaches 4.5:1 against the pane;
- **on-solid**: white or near-black, whichever reads better on the solid.

A color written with its own alpha keeps it as the tint. Today's UI (the Input's tints, tab and section dots, Settings' color swatches) switches to these roles, so the new colors are visible before any other v5 ticket lands. A first-launch config writes the new palette colors for the Built-in Patterns and Presets. Existing config files are left alone. The color resolution rules (shared names share one color, unused colors are taken first, then they cycle) don't change.

Spec: `.scratch/textier-v5/spec.md` (Implementation Decisions: Color roles, Palette). Visual reference: variant E of `.scratch/textier-v5/prototype-panel.html`. Vocabulary: `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The default palette and the User Pattern colors are the Radix hues listed in the spec
- [ ] Every default color yields text-on-pane and on-solid contrast of at least 4.5:1, in light and in dark
- [ ] Amber's on-solid is dark and blue's is white
- [ ] A single hex value, a light/dark pair, and a value with its own alpha all resolve to roles
- [ ] The Input's tints, the Inspector's dots and Settings' swatches draw from the roles
- [ ] A first-launch config file writes the new colors; an existing file is untouched, and a pinned `color` still wins
- [ ] `PatternColorTests` cover the roles and contrast; its resolution tests are updated to the new values and their rules are unchanged
