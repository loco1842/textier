# Folding in Raw JSON

Status: done (awaiting manual pass, step 83)

Raw JSON (the JSON Viewer's Raw, in the Inspector card and the Selection Popover, and the Match Window's editable Raw) can collapse and expand its nested objects and arrays, as a code editor folds.

## Decisions

1. **What folds:** an object or array whose closing bracket is on a later line than its opening one. Brackets inside strings don't count; text that isn't balanced JSON (a Match Window edit in progress) folds what does balance.
2. **Folded looks like:** `"key": {⋯}` — the opening bracket, a "⋯" placeholder, the closing bracket and what follows it on that line; the lines between are gone and the line numbers skip them, as in VS Code.
3. **The gutter:** a chevron after a foldable line's number, shown while the pointer is over the gutter, and always on a folded line; a click toggles it.
4. **Expanding:** a click on the "⋯", or the cursor or a selection end moving into the folded text (Go to Line, Find, arrows), expands it. An arrow moving onto a fold steps over it.
5. **Editing (Match Window):** folds stay folded while the text around them is edited; undo works as usual. An edit that runs into a folded block expands it; one that unbalances its brackets drops the fold. Beautify and View Original put back new text, without folds. The text is never changed by folding: copy, Go to Line and the model's text see all of it.
6. **Shortcuts:** Fold (⌥⌘[, the innermost block at the cursor) and Unfold (⌥⌘], the block at the cursor), customizable in Settings → Shortcuts like the others.
7. **Collapse all / Expand all:** the JSON Viewer's buttons work on Raw too, and the Match Window's Raw bar has them. Collapse all folds every block but the outermost, so the top-level keys show.
8. **Search:** what the card's Raw search finds is expanded.

## Not now

Folds aren't kept across switching Tree ↔ Raw, or across windows.
