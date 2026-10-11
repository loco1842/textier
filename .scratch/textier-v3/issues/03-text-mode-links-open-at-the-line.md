# 03: Text mode links open at the line

**What to build:** In the JSON Viewer's Text mode, clicking a paired `file` value's link opens the editor at its line, like the tree and the Inspector. Text mode asks the pairing seam's textual form over the beautified text it shows and gives those links the line.

Spec: `.scratch/textier-v3/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 02 (File/line pairing in the Inspector)

**Status:** ready-for-agent

- [ ] In Text mode on the Monolog JSON, clicking the `backtrace[0].file` link opens `EmailTemplateService.php` at line 80; the `caller_file` link opens at the top
- [ ] App tests cover the link targets carrying the paired line
