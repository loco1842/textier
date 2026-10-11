# textier v3: open backtrace frames at their line

Status: ready-for-agent

## Problem Statement

Monolog, like many loggers, writes a stack frame as an object with the path and the line in separate keys: `{"file": "/…/EmailTemplateService.php", "line": 80, "function": "__call"}`. textier detects the path as a file path Match, but the line sits in a sibling key it ignores, so Open in Editor lands at the top of the file and the developer has to read the line off the JSON and jump there by hand, once per frame. Stepping through a backtrace with ↓ and Return (the v2 done scenario) only pays off if each Return lands on the logged line.

## Solution

Inside one JSON object, a `file` key whose value is a file path Match and a `line` key holding a positive integer together mean `file:line`. Everywhere textier shows that path (the JSON Viewer's tree and Text mode, the Inspector's file path tab, Match Windows, escaped JSON parsed inline), opening it opens at the line, and a "Copy with Line" button copies `path:line`. Copy still copies the path exactly as logged. Nothing else pairs: the rule is the literal key names `file` and `line`, always on.

## User Stories

1. As a developer, I want a backtrace frame's `file` to open in my editor at the frame's `line`, so that I land on the logged line.
2. As a developer, I want that from the JSON Viewer's tree (double-click and the node toolbar's Open in Editor), so that I can open frames while reading the payload.
3. As a developer, I want it from the Inspector's file path tab (Open in Editor and Return), so that ↓ and Return step through the backtrace line by line.
4. As a developer, I want it from Text mode's file links, so that both JSON Viewer modes agree.
5. As a developer, I want the file path tab's preview to show `path:line` for a paired path, so that I can tell frames of the same file apart.
6. As a developer, I want the detail to show the line and say it came from the `line` key, so that I know textier paired it and didn't find it in the path.
7. As a developer, I want a "Copy with Line" button on a paired path, in the Action bar and in the node toolbar, so that I can paste `path:line` into a terminal or another tool.
8. As a developer, I want Copy to keep copying the path as logged, so that Copy always means "exactly what's there".
9. As a developer, I want a path that already ends in `:line` to keep its own line, so that the most specific value wins.
10. As a developer, I want `"line": 80` and `"line": "80"` both to count, and `0`, negatives, `null` and non-digit strings ignored, so that bad data never sends me to a wrong line.
11. As a developer, I want pairing inside escaped JSON parsed inline and in Match Windows, so that a Monolog `context` payload's backtrace works the same.
12. As a developer, I want pairing always on with nothing to configure, so that it just works.

## Implementation Decisions

Vocabulary follows `CONTEXT.md`. ADR-0002 (own JSON parser) applies.

### TextierCore: file/line pairing (new seam)

- The rule, in one place: an object whose `file` entry is a string that's a file path Match in its entirety (`stringValueMatch` with an `open-file` Pattern) and whose `line` entry is a positive integer (a JSON number with only digits, or a digit-only string) pairs. A path with its own `:line` keeps it. Only the first `file` and `line` entries of an object count (duplicate keys are kept by the parser).
- Structural form, for the JSON Viewer's tree: given an object's entries, the paired line for its `file` value, or nil.
- Textual form, for the Inspector and Text mode: given JSON text, the file/line targets in it, each with the UTF-16 range of the `file` string's content (inside the quotes, as written, escapes included) and the line. Built from the parser's existing tokens/positions; escaped JSON inside string values isn't searched (it's not structure in that text).
- `inspect` uses the textual form on each top-level JSON Match: a nested file path Match whose range equals a target's range gets the line. `FilePathDetail` carries the line, and where it came from (the path's own suffix or the sibling `line` key). The entry's `text` stays the path as logged; its preview shows `path:line`.

### Textier app

- Opening a file takes a path and a line instead of a Match's text, so a paired line reaches the editor (`Effects.openFile`, `Editor.open(path:line:)`).
- "Copy with Line" is an Action bar fixture like Pop Out, not a new `Action` (the config vocabulary stays closed). It appears only on a file path whose line came from the sibling key, in the Inspector's Action bar, a Match Window's, and the JSON Viewer's node toolbar.
- The JSON Viewer asks the structural form with the node's parent object; Text mode asks the textual form over the beautified text it shows. Escaped JSON parsed inline and Match Windows reuse the same code paths.
- The file path detail shows "Line 80 (from `line`)" for a paired line.

## Testing Decisions

- As in v1/v2, tests drive public TextierCore seams with realistic text; the Laravel/Monolog line is the canonical fixture.
- Pairing seam: on the Monolog JSON, the five backtrace `file` values pair with 80, 118, 603, 552, 479 and `caller_file` doesn't; number and digit-string lines pair; `0`, negative, `null`, `"80abc"`, a missing `line` and a non-path `file` don't; a path's own `:12` wins; target ranges are UTF-16 and point at the string's content (including a path with an escaped `\/` and a non-ASCII character before it).
- Inspection seam: the Monolog line's file path entries carry lines (`nil` for `caller_file`, 80… for the frames) with their source, previews end in `:line`, entry text stays the logged path; pairing inside a nested JSON Match works.
- App tests (`Tests/TextierAppTests`): Return on a paired file path entry, double-click on a paired tree value and Text mode's link all open at the line (recorded by the `Effects.openFile` stand-in); "Copy with Line" appears only on paired paths and copies `path:line`; Copy copies the path; escaped JSON parsed inline and a Match Window pair too.
- Prior art: `InspectionTests`, `JSONTreeTests`, `ColorizeTests`, `AppTests`.

## Out of Scope

- Other key names (`caller_file`/`caller_line`, `filename`/`lineno`, `fileName`/`lineNumber`, …), prefixes, and a configurable key list.
- Columns.
- Relative paths, or any new file path detection.
- A setting to turn pairing off.

## Further Notes

- The done scenario: capture the Monolog line, open the file path tab, step to the first backtrace frame with ↓, press Return: Cursor opens `EmailTemplateService.php` at line 80. In the JSON Viewer, double-click `backtrace[2].file`: `Dispatcher.php` opens at 603. "Copy with Line" on it gives `/…/Dispatcher.php:603`.
- `caller_file` stays unpaired by decision (its frame is `backtrace[1]`, which pairs).
