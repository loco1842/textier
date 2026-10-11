# 02: File/line pairing in the Inspector

**What to build:** Stepping through the file path tab with ↓ and Return lands on each frame's line. `TextierCore` gains the pairing rule's textual form: given JSON text, the file/line targets in it, each with the UTF-16 range of the `file` string's content (inside the quotes, as written) and the line. `inspect` applies it to each top-level JSON Match, so a nested file path entry whose range matches a target gets the line. `FilePathDetail` carries the line and its source (the path's own suffix or the sibling `line` key). The entry's preview shows `path:line`, its text stays the logged path, and the detail shows "Line 80 (from `line`)". Open in Editor and Return open at the line. The Action bar adds "Copy with Line" on a paired entry, in the Inspector and in Match Windows.

Spec: `.scratch/textier-v3/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (File/line pairing in the JSON Viewer's tree)

**Status:** ready-for-agent

- [ ] On the Monolog line, the file path tab previews the five backtrace frames as `…:80`, `…:118`, `…:603`, `…:552`, `…:479`; `caller_file` has no line
- [ ] Selecting the first frame and pressing Return opens `EmailTemplateService.php` at line 80
- [ ] The detail reads "Line 80 (from `line`)"; a path with its own `:12` shows line 12 without "(from `line`)"
- [ ] "Copy with Line" appears only on paired entries and copies `path:line`; Copy copies the path as logged
- [ ] Unit tests on the pairing seam's textual form cover target ranges (UTF-16, string content, an escaped `\/` and non-ASCII text before the path) and on the Inspection seam cover lines, sources and previews on the Monolog line
- [ ] App tests cover Return, "Copy with Line" and Copy on paired entries
