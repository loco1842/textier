# Sortable Matches

Status: ready-for-agent

Each Pattern's entries can be listed by position (as today) or sorted by value.

- **Orders**: every Pattern tab offers Position (default) and two value orders:
  - `datetime`: by the instant it means (mixed formats, offsets, epochs compare right; an offset-less one read as local, as its Summary is): Earliest first, Latest first.
  - `file path`: by path, then line as a number: A→Z, Z→A.
  - any other Pattern: by its text, numbers as numbers (`ORD-9` before `ORD-10`): A→Z, Z→A.
  - Plain Text isn't sortable; it keeps text order.
- **Ties and unreadable values** (a datetime that didn't parse): ties keep text order; unreadable entries come after the sorted ones, in text order.
- **Control**: in the Panel's tabs layout, a small sort menu at the right end of the tab bar for the selected tab, showing the current order ("Latest first ↓"); in the list layout, the same menu on each section header (shown on hover). In the Selection Popover, the same menu at the right end of the chip row, only while a chip filters to one Pattern (unfiltered stays text order).
- **Lifetime**: each tab has its own order, the Panel's and the Popover's apart. Edits and config reloads keep it; new text resets it to Position (a capture, a paste over the whole Input, Open in Panel, the shortcut).
- **Row numbers** keep each Match's position in the text (a sorted list reads 57, 3, 12…).
- **Selection**: the selected entry stays selected and scrolled to; arrows and Return follow the shown order; ⌘-clicking a Match selects its row wherever it is.

Tests: core for each order and its edge cases; app for the control, the reset rules and keeping the selection; manual steps for the look.
