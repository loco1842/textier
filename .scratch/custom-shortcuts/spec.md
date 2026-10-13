# Customizable shortcuts

Status: ready-for-agent

- **Commands** (defaults): the global shortcut (⌃⌥T, already customizable); Toggle Highlighting ⌘E; Switch Inspector Layout ⌘L; Pop Out ⌘⇧P; Go to Line ⌘G; Settings ⌘,; Quit ⌘Q; Toggle Wrap Lines (unassigned); Select Tab 1–9 (⌘ + digit: the modifier is customizable, the digits fixed); the Match click (⌘-click: the modifier is customizable). Text editing and navigation keys (⌘C/⌘V/⌘X/⌘Z/⌘A, arrows, Return, Tab, Esc) aren't.
- **Settings**: a new Shortcuts section in the sidebar: each command with a key recorder (as the global shortcut's) and a reset to its default, plus Restore Defaults.
- **Conflicts**: a shortcut another command has, one text editing uses (⌘C, ⌘V, ⌘X, ⌘Z, ⌘A), or one without ⌘, ⌃ or ⌥ is refused; the row keeps it as a draft and says why ("⌘G is already Go to Line"), as the global shortcut's recorder does.
- **Config file**: `"shortcut"` stays the global one; a new `"shortcuts"` object holds the commands, by key (`"goToLine": "cmd+g"`, `"toggleHighlighting": "cmd+e"`, …), written in full on first launch; a missing key takes its default, `""` unassigns it.
- **Shown everywhere**: tooltips, the Popover's "Open in Panel ⌃⌥T", the menu bar icon's menu key equivalents show the current shortcuts.
