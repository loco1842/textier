# 06: `open-file` and editor resolution

**What to build:** Double-clicking a file path Match opens the file in the user's editor at the right line. `TextierCore` gains a pure editor-command resolver taking the config `editorCommand` template, the resolved `$EDITOR` value (or none), a path and an optional line, and returning an argument vector. Precedence: `editorCommand` with `{path}` and `{line}` placeholders → `$EDITOR`, where known GUI editors get their line flag (`cursor`, `code` → `-g {path}:{line}`; `zed`, `subl` → `{path}:{line}`) and unknown editors get `{editor} {path}` → the default `cursor -g {path}:{line}`. The app resolves `$EDITOR` once at launch by running the user's login shell non-interactively (GUI apps don't inherit shell exports) and caches it. The `open-file` Action declared in ticket 03 becomes live: it runs the resolved command as a subprocess, passing the `:line` from the Match when present. The menu bar gains Open Config File, which opens the config path through the same resolver.

Spec: `.scratch/textier-v1/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 03 (Presets and overlap/nesting rules), 05 (Config file)

**Status:** done

- [x] With `editorCommand` unset and `$EDITOR` unset, double-clicking `/path/File.php:118` opens it in Cursor at line 118
- [x] With `export EDITOR=code` in the login shell, the same Match opens in VS Code at the line
- [x] With `editorCommand: "zed {path}:{line}"` in config, it opens in Zed; config wins over `$EDITOR`
- [x] A path without a line suffix opens without a line argument
- [x] Open Config File menu item opens `~/.config/textier/config.json` in the same editor
- [x] Unit tests on the resolver cover every precedence branch, each known GUI editor, unknown editor, placeholder substitution, and missing line

## Comments

**2026-10-08, implementation:** Built and committed. 104 tests pass (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`).
- **Core API** (`Sources/TextierCore/EditorCommand.swift`):
  - `EditorCommand.arguments(template:editor:path:line:) -> [String]` returns the argument vector, executable first.
  - Precedence: `editorCommand` → `$EDITOR` → `cursor -g {path}:{line}`. A blank template or `$EDITOR` counts as unset.
  - Templates are split shell-style (spaces separate arguments; `'…'`, `"…"` and `\` quote), then `{path}` and `{line}` are filled inside each argument, so a path with spaces stays one argument.
  - With no line, a template drops `:{line}`, and drops a bare `{line}` argument together with the flag right before it (`--line {line}`).
  - A template without `{path}` gets the path appended.
  - `$EDITOR` may carry flags (`code --wait`). The editor is recognised by its basename (`/usr/local/bin/code` counts as `code`). Known GUI editors get their line argument, and just the path when there's no line. An unknown editor gets `{editor} {path}`.
  - `FileLocation(matchText:homeDirectory:)` splits `/a/b.php:118:5` into path, line and column, and expands `~/`.
- **Spec change, recorded in the spec:** this machine's login shell has `EDITOR=vi`. textier runs the editor without a terminal, so `vi` would fail or hang. Terminal editors (`vi`, `vim`, `nvim`, `nano`, `emacs`, `hx`, `micro`, …) in `$EDITOR` now fall through to the default, `cursor`. Set `editorCommand` to choose something else.
- **App** (`Sources/Textier/Editor.swift`):
  - At launch, textier runs `$SHELL -l -i -c` once, in the background, to read `$EDITOR` and `$PATH`, then caches them.
  - The shell is interactive because both are commonly set in `.zshrc`, which a non-interactive login shell skips. Its stdin is empty, a marker separates the values from anything the rc files print, and it gives up after 10 s. Here it took about 3 s.
  - Commands run via `/usr/bin/env` with that `PATH`. A login shell per open would add its startup time to every click, and the GUI `PATH` can't find `/usr/local/bin/cursor`.
  - If the command can't launch or exits non-zero (127 when it isn't found), the file opens with macOS `open` instead.
  - The `open-file` Action is live. Open Config File sits in the menu between Open Panel and Reload Config, and goes through the same resolver with no line.
- **Verified:**
  - In the running debug app, the login shell lookup logs `$EDITOR is vi`.
  - From a shell: `/usr/bin/env` finds `cursor` with the resolved `PATH` but not with the GUI `PATH`; a missing command exits 127; argv paths with spaces stay one argument.
  - No editor was actually opened, and no UI was driven.
- **Still to check by hand:**
  - Double-clicking `…/SendLoginFromNewIPEmailToPlayer.php:118` opens Cursor at line 118. That's the default here, because `vi` is skipped.
  - With `export EDITOR=code`, the same Match opens in VS Code at the line.
  - With `"editorCommand": "zed {path}:{line}"`, it opens in Zed; the config wins over `$EDITOR`.
  - A path without a line suffix opens with no line argument.
  - Open Config File opens the config in the same editor.

**2026-10-08, follow-up (code review):** When the editor command can't launch or exits non-zero and the file falls back to macOS `open`, a warning ("Couldn't run `…` (command not found / exit N); opened it with the default app") shows in the Panel footer and the menu bar badge. It clears on the next successful editor launch or a config reload. Check by hand: set `"editorCommand": "nosuchedit {path}"`, double-click a file path, the file opens in the default app and the warning appears; fix the command, open again, and the warning clears.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v1/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
