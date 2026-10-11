# textier v5: a modern, colorful Panel

Status: ready-for-agent

## Problem Statement

textier works, but it looks like a utility someone wired together from stock controls. The Panel is a plain utility window with a title bar, a toolbar of a toggle and a segmented picker, and grey dividers between every area. Matches in the Input are a pale tint with an underline in muted GitHub hues, which are hard to tell apart in dark mode. The Inspector is an ordinary list: a small dot is the only sign of which Pattern a tab is for, and each row repeats the raw text of the Match, so you have to select a row to learn what the Match means (which day that timestamp is, which file that path opens, how big that JSON object is). The Match Window looks like a second, different app. Warnings sit in an orange line at the bottom. Nothing about it feels like a tool from 2026, and the color, which is the one thing that tells Patterns apart, is too faint to do that job.

## Solution

The Panel becomes a borderless, frosted floating panel in the style of Spotlight and Raycast, laid out on macOS Tahoe's rules: no title bar or traffic lights, no dividers, soft fades at scroll edges, and corners that nest (window, then an inset Inspector pane, then rows and cards inside it). Pattern colors carry the design: a more saturated palette, Matches in the Input drawn as rounded colored pills, Inspector tabs as pills in their Pattern's color with the Pattern's Glyph, and the primary Action filled in the selected Match's color. Each Inspector row leads with a Summary of what the Match means, with the raw text faint below it. Parsed views sit in cards. The header holds only the two controls, a color-bar summary of the Input and a warnings badge. The Match Window gets the same look and keeps its traffic lights.

Behaviour doesn't change: every shortcut, both Inspector layouts, selection, Actions, Pop Out and the config file work as they do today.

The visual reference is variant **E** of the throwaway mockup `.scratch/textier-v5/prototype-panel.html` (published at https://claude.ai/artifact/A4Vt3jJC6ZBRY79TZub9Lc, which opens on E). Its other variants are explorations that weren't chosen.

## User Stories

### The Panel window

1. As a developer, I want the Panel to be a borderless floating panel with no title bar and no traffic lights, so that it feels like a launcher I summon and dismiss.
2. As a developer, I want the Panel's background to be a frosted material that blurs what's behind it, so that it looks current and sits lightly over my work.
3. As a developer, I want the Panel to follow the system's light or dark appearance, so that it matches the rest of my Mac.
4. As a developer, I want the Panel to fall back to an opaque background when "Reduce Transparency" is on, so that it stays readable for people who need that.
5. As a developer, I want to move the Panel by dragging its header, so that I can still put it where I want without a title bar.
6. As a developer, I want to resize the Panel from its edges, so that I can give long logs more room.
7. As a developer, I want the Panel to remember its size and the Input/Inspector divider position, so that it opens the way I left it, as it does today.
8. As a developer, I want Esc to close the Panel and the global shortcut to open it, as today, so that losing the close button costs me nothing.
9. As a developer, I want the window, the Inspector pane and the rows and cards inside it to have concentric rounded corners, so that the layers read as one designed object.
10. As a developer, I want no divider lines between the header, the Input, the Inspector and the Action bar, so that the Panel looks clean; content fades at its scroll edges instead.

### The header

11. As a developer, I want the Highlighting toggle and the Tabs/List layout control as two small glass icon buttons in the header, so that they're there without a toolbar.
12. As a developer, I want ⌘E and ⌘L to keep working, so that the new buttons change nothing about how I drive textier.
13. As a developer, I want the header to summarize the Input as a small color bar (one segment per Pattern, sized by its Match count) and "N Patterns · M Matches", so that I see the shape of what was found at a glance.
14. As a developer, I want config warnings as a small "⚠ N" badge in the header, so that they don't take a whole line at the bottom.
15. As a developer, I want clicking the warnings badge to open a popover listing every warning in full, so that I can read them without a tooltip.
16. As a developer, I want the warnings badge to disappear when there are no warnings, so that a healthy setup shows nothing extra.
17. As a developer, I want the Panel to have no footer, so that the Input and the Inspector get all the height.

### The Input

18. As a developer, I want each top-level Match in the Input drawn as a rounded pill tinted in its Pattern's color, with its text in that color, so that Matches stand out clearly.
19. As a developer, I want no underline under Matches, so that the pills look clean.
20. As a developer, I want a Match that wraps across lines to get a rounded pill piece on each line, so that wrapped JSON still looks deliberate.
21. As a developer, I want the Match selected in the Inspector to show in the Input with a stronger tint and a ring in its Pattern's color (a nested Match too, inside its parent's pill), so that I can see where the selected Match sits in my text.
22. As a developer, I want hovering a pill to deepen its tint, so that it's clear the pill is clickable.
23. As a developer, I want Highlighting off to remove the pills, and click-to-copy and double-click-to-inspect to behave as they do today, so that nothing about editing changes.
24. As a developer, I want an empty Input to show a faint placeholder, "Paste or type text — ⌘V", so that a fresh Panel tells me what to do.

### The Inspector

25. As a developer, I want the Inspector to be a pane inset from the window's edges, one step lighter than the window's material (darker in dark mode), with rounded corners and a soft shadow, so that it reads as a layer floating inside the Panel.
26. As a developer, I want the Inspector pane to stay readable over any wallpaper, so that the frosted look never costs legibility (it is a material layer, not refractive glass).
27. As a developer, I want the Inspector to slide and fade in when the Input gets its first Match, so that its appearance feels intentional.
28. As a developer, I want each tab to be a pill tinted in its Pattern's color, showing the Pattern's Glyph, its name and its Match count, so that I can tell tabs apart by color and shape.
29. As a developer, I want the selected tab to be filled solid in its Pattern's color, so that I always know which tab I'm on.
30. As a developer, I want the text on a solid fill to be whatever reads best on that color (dark on amber, white on blue), so that every selected tab and primary button is legible.
31. As a developer, I want the Plain Text tab to be a neutral grey pill with its own Glyph, so that it's clearly not a Pattern.
32. As a developer, I want ⌘1…⌘9 to keep selecting tabs, so that the redesign doesn't break my muscle memory.
33. As a developer, I want each row to have a short bar in its Pattern's color at its leading edge, so that List-layout rows show their Pattern too.
34. As a developer, I want each row to show the Match's Summary on top and its raw text faint below, so that I can see what each Match means without selecting it.
35. As a developer, I want a row whose Match has no Summary to stay one line of raw text, so that log levels and Plain Text don't repeat themselves.
36. As a developer, I want the selected row tinted in its own Pattern's color instead of the system accent, so that the selection matches the rest of the colors.
37. As a developer, I want a nested Match's parent tag shown as a chip tinted in the parent's Pattern color, so that I can see which Match it sits inside at a glance.
38. As a developer, I want the List layout's section headers to show the Pattern's Glyph and a count chip, so that both layouts speak the same visual language.
39. As a developer, I want the row list and the parsed view below it to stay resizable against each other, with no visible divider line, so that I keep today's control without the line.
40. As a developer, I want Tab and Shift-Tab, the arrow keys, Return and double-click to work in the rows as they do today, so that keyboard use is unchanged.

### Summaries

41. As a developer, I want a datetime's Summary to be its local time and how long ago it was (with the date when it isn't today), so that I can read a timestamp in my own time zone at a glance.
42. As a developer, I want a datetime written without an offset to follow the same "read as UTC" choice the parsed view uses, so that the Summary and the detail never disagree.
43. As a developer, I want a file path's Summary to be the file's name and its line and column, so that I can tell paths apart without reading the whole path.
44. As a developer, I want a URL's Summary to be its host, so that I can see where a link goes.
45. As a developer, I want a JSON Match's Summary to be its size and first keys ("6 keys · orderId, amount, currency…") or, for an array, its item count, so that I know what an object holds before I open it.
46. As a developer, I want a regex Pattern's Match that has Fields to show its first Fields as its Summary ("client 10.0.0.4 · method GET"), so that a whole parsed log line reads as its parts.
47. As a developer, I want a Match with no parsed view and no Fields (a log level, a User Pattern without named captures) and Plain Text to have no Summary, so that rows never say the same thing twice.

### Glyphs

48. As a developer, I want every Built-in Pattern and Preset to have its own Glyph (braces for JSON, a link for URL, a clock for datetime, a document for file path, a flag for log level), so that Patterns are recognisable by shape as well as color.
49. As a developer, I want all User Patterns to share one generic Glyph, so that my own Patterns are marked consistently while their colors tell them apart.
50. As a developer, I want a group of Patterns that share a name to take the Glyph of the group's first Pattern, so that one tab has one Glyph, as it has one color.
51. As a developer, I want the Glyph to appear wherever the Pattern's name does in the Panel and Match Window (tabs, List section headers, the Match Window's title), so that the mark is consistent.

### Actions

52. As a developer, I want the selected entry's first Action as a pill filled in its Pattern's color, with a "↩" hint, so that I know what Return will do.
53. As a developer, I want the other Actions as borderless pill buttons with an icon and a label, so that the bar stays quiet.
54. As a developer, I want the Action bar to stay hidden while nothing is selected, as today, so that an empty Inspector shows nothing to click.

### Parsed views

55. As a developer, I want the parsed view of the selected entry in a rounded card inset in the Inspector pane, so that "card" always means "a parsed Match".
56. As a developer, I want the JSON Viewer's card to keep its VS Code theme's background and colors, so that JSON looks exactly as the theme intends (ADR-0003).
57. As a developer, I want URL, datetime, file path, Fields and text views in a neutral card with label/value rows, so that every parsed view looks like part of one family.

### Colors

58. As a developer, I want the default Pattern colors to be a more saturated palette (Radix hues: amber for JSON, orange for escaped JSON, blue for URL, violet for datetime, green for file path, red for log level), so that Patterns are easy to tell apart in both light and dark mode.
59. As a developer, I want User Patterns without a color to take the next unused color from a saturated set (pink, cyan, lime, purple, grey), so that my own Patterns look as good as the built-in ones.
60. As a developer, I want a color I set in the config, as one hex value or a light/dark pair, to keep working and to drive every role (pill, selected tint, solid fill, text) from that one value, so that I never have to specify five shades.
61. As a developer, I want Patterns that share a name to keep sharing one color, so that groups stay one color, as they are today.
62. As a developer, I want a first-launch config file to write the new palette's colors for the Built-in Patterns and Presets, so that the file documents the colors I'm actually seeing.
63. As a developer, I want my existing config file to be left as it is, so that Patterns without a color simply pick up the new palette and colors I pinned stay pinned.

### Match Window

64. As a developer, I want a Match Window to use the same frosted material, corners, cards and Pattern colors as the Panel, so that the two windows look like one app.
65. As a developer, I want a Match Window to keep its traffic lights in a transparent header with no title text, so that I can still close, minimise and zoom the windows I keep open.
66. As a developer, I want a Match Window's header to show a solid pill with the Pattern's Glyph, name and index, the Match's one-line preview, and the Action bar, so that the window says what it holds and what I can do with it.
67. As a developer, I want a Match Window to have no line under its header, so that it matches the Panel.

### Motion and accessibility

68. As a developer, I want switching tabs and moving the selection to animate with a short spring, so that the UI feels responsive.
69. As a developer, I want no animation at all when "Reduce Motion" is on, so that the Panel respects my system setting.
70. As a developer, I want every color pairing to pass contrast in both appearances, so that the new color never costs readability.
71. As a developer, I want VoiceOver to read the new controls (header buttons, the warnings badge, tabs with their counts, rows with their Summary), so that the redesign is no less accessible than today.

## Implementation Decisions

- **Platform.** The deployment target moves from macOS 15 to macOS 26 so the header controls and Action buttons can use the system glass effect. textier is still for one user, built locally (see the v1 decisions), so nothing else depends on macOS 15.
- **Glass only on controls.** Liquid Glass is used for the header's icon buttons and may be used for the Action bar's buttons. Content surfaces (the window background, the Inspector pane, cards) use materials: the window a frosted vibrancy material, the Inspector pane that material one step lighter (darker in dark mode) with a soft shadow, and not a second blur. This keeps content readable over any wallpaper, which is Apple's guidance for glass.
- **Panel window.** The Panel shows no title bar and no traffic lights, has a frosted full-window background, stays floating, resizable and centered on open, and closes with Esc. A borderless panel that can become key, or a titled panel with a full-size transparent title bar and hidden standard buttons, both work. Pick whichever gives rounded corners close to the mockup's (26 pt) and keeps edge resizing and remembered sizes working. The header strip (52 pt) drags the window.
- **Layout geometry, from the mockup (variant E).** Window corner 26 pt. The Inspector pane is inset 8 pt from the window's right and bottom edges, corner 18 pt. Rows, cards and the selected-row tint inside the pane have corner 10 pt and are inset 8 pt. The Input/Inspector split keeps its remembered position, and the Inspector's list/detail split stays resizable. Both dividers are made invisible but stay draggable.
- **No dividers.** All `Divider`s and hairlines in the Panel and Match Window go. Scrolling areas (the Input, the row list) fade their content at the top and bottom edges instead.
- **Header contents, left to right.** The Highlighting toggle (one glass icon button), the Tabs/List control (two glass icon buttons as a pair), a flexible space, the color-bar summary with "N Patterns · M Matches" (shown only when the Inspector is), and the warnings badge (shown only with warnings), which opens a popover listing all warnings. The warnings footer is removed.
- **Input highlighting.** The tinted background plus underline becomes a rounded pill drawn by the Input's text layout: one rounded rectangle per line fragment a Match covers, filled with the Pattern's tint, the Match text drawn in the Pattern's text color, and no underline. The entry selected in the Inspector (its range, for a nested Match too) gets the strong tint and a 1.5 pt ring in the solid color. Hover deepens the tint. Highlighting off draws nothing, as today. Click and double-click behaviour is unchanged.
- **Color roles (core).** `PatternColor` stays the config's one value (or light/dark pair). A new core function derives, per appearance, the roles the UI draws with: **tint** (pill and tab at rest), **strong tint** (hover, selected Match, selected row), **solid** (the selected tab, the primary Action, row bars, rings, the header's color bar), **text** (a pill's text and colored labels, adjusted toward black in light mode or white in dark mode until it reaches 4.5:1 against the pane), and **on-solid** (white or near-black, whichever contrasts better with the solid). A value written with its own alpha keeps it as the tint, as today. The app turns roles into `NSColor`/`Color`; the derivation itself is pure and lives in the core library next to `Palette`.
- **Palette.** `Palette.byName` moves to Radix step-9 hues (amber `#ffc53d`, orange `#f76b15`, blue `#0090ff`, violet `#6e56cf`, green `#46a758`, red `#e5484d`), and `Palette.forUserPatterns` to Radix pink, cyan, lime, purple and grey. The exact light/dark values may be tuned against the derived roles so that tint, text and on-solid come out close to the mockup. The color resolution rules (shared names share the first Pattern's color, unused colors before cycling) are unchanged. The Built-in Patterns and Presets keep writing their palette color into a first-launch config. Existing config files are not rewritten.
- **Glyph (core).** A new core value says which Glyph a tab shows: one case per Built-in Pattern (`json`, `escaped-json`), one per Preset (`url`, `datetime`, `file path`, `log level`), one shared by all User Patterns, and one for Plain Text. A Pattern name's Glyph is decided by its group's first Pattern, using the rule `CONTEXT.md` gives for telling a Preset apart: the first regex Pattern with a Preset's name is that Preset. The app maps each case to an SF Symbol (for example `curlybraces`, `link`, `clock`, `doc.text`, `flag`, `text.alignleft`, and a regex-like mark for User Patterns). `InspectorTab` gains its Glyph.
- **Summary (core).** `InspectorEntry` gains an optional Summary, computed in `inspect` alongside the entry's detail and Fields, with the same `now` and time zone. The rules, first that applies:
  - a datetime detail: local time `HH:mm:ss` (prefixed with the date when it isn't today in the local time zone), then "·" and the relative time the parsed view already computes. For a datetime written without an offset, the core gives both readings (assumed local, read as UTC), the way the datetime detail already carries both, and the row shows the one the Panel's "read as UTC" choice picks;
  - a file path detail: the last path component, then "· line L, col C" (or "· line L", or nothing more) from the detail;
  - a URL detail: the host;
  - a JSON detail: "N keys · k1, k2, k3…" for an object (up to three keys, "…" when there are more), "N items" for an array, with "key"/"item" singular for one;
  - otherwise, when the entry has Fields: the first Fields as "label value" pairs joined by " · ", up to three;
  - otherwise none. Log level, User Patterns without Fields, and every Plain Text entry have no Summary. A Summary equal to the entry's text is also dropped.

  The Summary is one line and is not truncated in the core; the row truncates it.
- **Rows.** Each row has a 3 pt bar in the Pattern's solid color, the entry's index (numbering unchanged), then either two lines (the Summary in the primary text color, the raw one-line preview faint and monospaced below) or one line (the preview) when there's no Summary, and the parent chip. The parent chip is tinted in the parent Pattern's color, which `ParentTag`'s Pattern name gives. The selected row's background is the row's own strong tint, and the system selection highlight is suppressed. Keyboard focus is still shown.
- **Tabs.** Pills with the Glyph, the name and the count, at rest in tint with text in the text color, and selected in solid with on-solid text and Glyph. They scroll horizontally when they overflow, as today. List-layout section headers show the disclosure, Glyph, name and a count chip.
- **Action bar.** The first Action is a pill filled with the entry's solid color, with on-solid text and a "↩" hint. The others are borderless pill buttons with an SF Symbol and a label (copy, globe for Open in Browser, `chevron.left.forwardslash.chevron.right` for Open in Editor, a sparkle or wand for Copy Beautified, and a pop-out mark for Pop Out). Plain Text keeps Copy only. What each Action does is unchanged.
- **Cards.** The detail view sits in a card (corner 10 pt, inset 8 pt) at the bottom of the Inspector pane. The JSON Viewer's card is filled with the active VS Code theme's background (ADR-0003 unchanged). Other details use a neutral card fill, with label/value rows separated by faint lines inside the card only. Copy buttons on rows appear on hover.
- **Match Window.** Same material, corners and cards. It keeps its traffic lights in a transparent, full-size-content title bar, with the title hidden (the window title stays set for the Window menu and accessibility). Its header holds the solid title pill (Glyph, Pattern name, index), the one-line preview and the Action bar without Pop Out. The card fills the rest.
- **Empty state.** The Input shows the placeholder "Paste or type text — ⌘V" when empty. With no Matches the Inspector stays hidden, as today.
- **Motion.** The Inspector fades and slides in (about 0.25 s) when it first appears. Tab and selection changes animate with a short spring. Everything is off when "Reduce Motion" is on.
- **Unchanged.** Detection, Actions, the config file format, Settings (beyond picking up the new palette in its color swatches), the menu bar extra, the JSON Viewer's tree behaviour and coloring, Match Window behaviour, and every keyboard shortcut.

## Testing Decisions

- **What a good test is here.** It drives the public seam and checks what a user would see in the model: given this Input and Config, these tabs, Glyphs and Summaries; given this color, these roles. It does not assert on view hierarchies, SwiftUI modifiers or drawing code.
- **Seam 1: `inspect` (core).** New cases in the style of `InspectionTests` and `FieldTests`: an Input holding a datetime (today and another day, with and without an offset, under both UTC readings), a file path (with and without line and column), a URL, a JSON object (more and fewer than three keys) and a JSON array, a regex Pattern with Fields (more than three, and none), a log level and Plain Text. Each case checks the entry's Summary, or that it has none. Glyph cases: each Built-in Pattern and Preset, a User Pattern, two regex Patterns named `url` in either order (the url Glyph either way, since the first is the Preset by definition), a User Pattern with its own name, and Plain Text. Fixed `now` and time zone, as the datetime tests already use.
- **Seam 2: color roles (core).** New cases in `PatternColorTests`: each default palette color yields roles whose text-on-pane and on-solid contrast pass 4.5:1 in light and dark. Amber's on-solid is dark and blue's is white. A single hex value and a light/dark pair both resolve. A value with its own alpha keeps it as the tint. The existing resolution tests (shared names, unused-first, cycling) are updated to the new palette values; the rules they check don't change.
- **Seam 3: the app harness, for behaviour only.** In `PanelTests`: the Panel still becomes key with the Input focused, Esc still closes it, and its size and divider position are still restored, now with no title bar. All existing `InspectorTests`, `ListLayoutTests`, `InputTests` and `JSONViewerTests` must pass unchanged, which is the evidence that behaviour didn't change. Where a test reached for a removed view (a `Divider`, the footer text), it moves to the model property the new view reads (for example the warnings list).
- **The look is checked by hand.** The harness renders materials blank (`docs/agents/testing.md`), so snapshot tests of the frosted surfaces would compare empty rectangles. Once the tickets are done, a `.scratch/textier-v5/manual-test.txt` is written like v1–v4's. It walks light and dark, Reduce Transparency and Reduce Motion, each Pattern's pill, tab and row, nested selection, the warnings badge, the empty placeholder, the List layout and a Match Window, comparing each against mockup variant E.
- **Running.** Core tests with `scripts/test.sh --skip TextierAppTests`, everything with `scripts/test.sh`. `ListLayoutTests.commandLSwitchesTheLayoutAndItHoldsAcrossCaptures` is known to be flaky; rerun it alone before treating it as a regression.

## Out of Scope

- Settings and the menu bar extra keep their current look (Settings only picks up the new palette in its swatches).
- Letting a User Pattern choose its Glyph (a `glyph` config field and a Settings control). User Patterns share one Glyph in v5.
- A minimap or line gutter in the Input, and a window glow in the selected Pattern's color. Both were considered and declined.
- Ideas from the mockup's other variants: a filter field, a ⌘K Action menu, inline peeks, margin notes, an event timeline, a filmstrip, a feed, a bento overview, a menu bar popover.
- Liquid Glass on content surfaces.
- Any change to how the JSON Viewer colors JSON (ADR-0003), to detection, to Actions or to the config format.
- Snapshot or pixel tests of the UI.
- Supporting macOS versions before 26.

## Further Notes

- Glossary: this spec uses **Glyph** and **Summary**, added to `CONTEXT.md` during the design session. "Preview" stays the raw one-line text in the code; don't call the Summary a preview.
- The mockup numbers entries from 1 ("json 1"). The app keeps numbering them from 0 as it does today ("in json 0"), since v5 changes no behaviour. Switching to 1-based would be a separate, small decision.
- The mockup is throwaway code (inline HTML/CSS/JS). Read its variant E for proportions, spacing, colors and states, not for implementation. Per the prototype skill, it belongs on a throwaway branch, not on `main`, once the design has been folded into the app.
- The artifact behind the mockup has been edited by another session too (variants G–Q). Re-read it before republishing it.
- Don't run `scripts/bundle.sh` while the user is hand-testing `build/Textier.app`: a rebuild drops the Accessibility grant.
