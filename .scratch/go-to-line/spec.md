# Go to Line, and ⌘-click on a Match

Status: ready-for-agent

## Go to Line (⌘G)

- In the Panel's Input and a Match Window's Raw editor.
- A small field over the top of the text, VS Code style: "Go to line (1–12,345), or line:column". Return jumps, Esc or a click elsewhere closes it.
- Lines as the gutter numbers them (a wrapped line counts once). `120` goes to line 120's start, `120:15` to its 15th column; past the end goes to the last line; anything else isn't accepted.
- The cursor lands there, the line scrolls to the middle and flashes briefly; the gutter's current-line highlight follows.

## Clicks in the text

- A plain click in the Input is a text click everywhere, pills included: it places the cursor, a drag selects, a double-click selects a word, a triple-click a line. It no longer selects the entry, and a double-click no longer copies the Match.
- ⌘-click on a pill selects its entry in the Inspector (ringing it, opening its card, selecting its text, so ⌘C copies it).
- The pointing hand and the pill's hover tint show only while ⌘ is held.
- The Selection Popover's preview follows the same rule (⌘-click selects the row).
- The modifier is customizable (`custom-shortcuts`).
