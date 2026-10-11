# 09: Syntax coloring with VS Code themes

**What to build:** JSON in the Inspector and Match Windows is colored like VS Code, per ADR-0003. `TextierCore` gains the syntax-coloring seam: `Theme.load` reads a VS Code theme JSON (`tokenColors` scope rules and editor colors) and resolves the scopes JSON uses; `colorize(JSON text, theme)` returns UTF-16 ranges with color and font style from the existing JSON scanner's tokens (escaped JSON inside strings colors as a string). GitHub Light and GitHub Dark ship bundled and follow the system appearance. A new optional `theme` config key (`{"light": path, "dark": path}`, relative to the config file's folder or absolute) loads user theme files; a missing or broken one warns and falls back to the bundled default. The Text mode is colored, and tree values use the same theme colors.

Spec: `.scratch/textier-v2/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 08 (JSON Viewer in the Inspector)

**Status:** done

- [x] The Monolog JSON in Text mode shows keys, strings, numbers and literals in distinct GitHub colors; switching appearance switches theme
- [x] Tree values use the same colors
- [x] Pointing `theme.dark` at a VS Code theme file changes the colors after save; a broken path warns and falls back
- [x] Unit tests on the syntax-coloring seam cover loading the bundled themes, distinct scope colors on the Monolog JSON, UTF-16 ranges that cover the text without overlap, a malformed theme rejected, and a user theme overriding the string scope

## Comments

**2026-10-09, implementation:** Built and committed; unit tests pass. Bundled themes: GitHub Light Default and GitHub Dark Default from `GitHub.github-vscode-theme` 6.3.5 (MIT), embedded as Swift string literals in `BundledThemes.swift` rather than SwiftPM resources. In both GitHub themes numbers and `true`/`false`/`null` share one color (as in VS Code), so the test asserts keys, strings, numbers and punctuation are distinct and literals differ from keys and strings; a custom-theme test shows they separate when a theme sets them.
- Automated: the matching suites in `Tests/TextierAppTests` cover the acceptance criteria in-process. Still to check by hand: steps 9 of `.scratch/textier-v2/manual-test.txt`.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
