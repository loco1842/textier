# 01: File/line pairing in the JSON Viewer's tree

**What to build:** A backtrace frame opens at its line from the JSON Viewer's tree. `TextierCore` gains the pairing rule in its structural form: given a JSON object's entries, the line paired with its `file` value. That's a `file` string that's a file path Match in its entirety plus a `line` that's a positive integer (number or digit-only string); the path's own `:line` wins, and only the literal keys `file` and `line` count. Opening a file now takes a path and a line (`Effects.openFile`, `Editor.open(path:line:)`), so the tree's double-click and the node toolbar's Open in Editor on a paired `file` value open at the line. The node toolbar adds "Copy with Line" (`path:line`) on a paired value; Copy Value still copies the path. It works the same in escaped JSON parsed inline and in Match Windows.

Spec: `.scratch/textier-v3/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Double-clicking `backtrace[0].file` on the Monolog line opens `EmailTemplateService.php` at line 80; `backtrace[2].file` opens `Dispatcher.php` at 603
- [ ] `caller_file` opens at the top (no pairing)
- [ ] "Copy with Line" shows only on paired `file` values and copies `/…/Dispatcher.php:603`; Copy Value copies the path
- [ ] A frame inside escaped JSON parsed inline, and in a Match Window, pairs the same way
- [ ] Unit tests on the pairing seam cover the Monolog frames, number and digit-string lines, rejected lines (`0`, negative, `null`, `"80abc"`, missing), a non-path `file`, and a path with its own `:12`
- [ ] App tests cover double-click and "Copy with Line" through the `Effects` stand-ins
