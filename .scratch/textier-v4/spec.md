# textier v4: Settings, grok and Perl-style Patterns

Status: done

## Problem Statement

Everything textier can be told lives in a hand-edited JSON file. Adding a Pattern means writing a regex as an escaped JSON string, saving, glancing at the menu bar for a warning ("invalid regex", with no reason), and then capturing something to see whether it matched. There's no way to try a regex against real text while writing it. Regexes for common log pieces (an IPv4 address, an ISO timestamp, a Java class) have to be written from scratch even though grok libraries have had them for years. Regexes pasted from elsewhere use Perl/PCRE spellings (`(?P<name>…)`) that textier rejects, or constructs like `\K` that it silently reads as something else. And once a Pattern matches a whole log line, textier shows it as one blob of text: the parts the regex already names (`(?<client>…)`) are thrown away.

Patterns can also already share a name (a float and an integer Pattern both named `numeric`), and the Inspector groups them into one tab, but the rest of the app looks a Pattern up by name and takes the first, so the second Pattern's Actions get lost, and each Pattern gets its own color inside one group.

## Solution

A Settings window edits the config file: the shortcut, the editor, appearance, the Patterns and the Grok Definitions. It saves as you go, and the file stays the source of truth, so hand edits still work. Its Pattern editor has a live test box, pre-filled with the Panel's Input, that shows the Matches and Fields as you type, with errors that name what's wrong.

Patterns are written in Perl-style regex (ADR-0004): the everyday Perl syntax works, the Python/PHP named-group spellings are accepted, and anything textier can't run is an error that says so. A Pattern's regex can use grok: `%{NAME}` expands a Grok Definition, from the bundled library (StreamSets' 69 names) or the user's own. Named captures, `%{IP:client}` or `(?<client>…)`, become Fields: labelled rows in the Match's parsed view.

Patterns that share a name share one Inspector group and one color, and each Match keeps the Actions of the Pattern that found it.

## User Stories

### Settings window

1. As a developer, I want a Settings window, so that I can change textier without editing JSON by hand.
2. As a developer, I want to open Settings from the menu bar ("Settings…") and with ⌘, in the Panel, so that it's where Mac apps keep it.
3. As a developer, I want Settings to edit the same config file I can edit by hand, so that my dotfiles keep working and I can still diff and share the file.
4. As a developer, I want every valid change to save at once, so that I never have to remember a Save button.
5. As a developer, I want the Panel to follow a change as soon as it's saved, so that I can see its effect immediately.
6. As a developer, I want an invalid value to be shown inline and not saved, so that the file only ever holds settings that work.
7. As a developer, I want Settings to reload when I save the config file in my editor, so that the window never shows stale values.
8. As a developer, I want a broken draft I'm still fixing to survive a reload, with a note that the file changed underneath it, so that I don't lose my typing.
9. As a developer, I want config warnings shown in the section they belong to, with a way to jump to the cause, so that I can fix them where they are.
10. As a developer, I want "Open Config File" to stay in the menu bar, so that I can still edit the file directly.
11. As a developer, I want "Reload Config" gone, so that the menu doesn't offer something that now happens by itself.

### General and Appearance

12. As a developer, I want to set the global shortcut by pressing it, so that I don't have to spell `ctrl+option+t`.
13. As a developer, I want to be told when the shortcut I pressed can't be registered, so that I don't end up without one.
14. As a developer, I want to set the editor command and test it, so that I know Open in Editor will work before I need it.
15. As a developer, I want to choose what a click on JSON copies (raw or beautified), so that it matches how I paste.
16. As a developer, I want to choose the Inspector layout (tabs or list), so that the default suits my Inputs.
17. As a developer, I want to pick a theme file for light and dark appearance, so that the JSON Viewer matches my editor.

### Patterns in Settings

18. As a developer, I want every Pattern listed in priority order, so that I can see what wins when two overlap.
19. As a developer, I want to drag Patterns to reorder them, so that I can change priority.
20. As a developer, I want to turn a Pattern on and off with a switch, so that I can silence one without deleting it.
21. As a developer, I want each row to show the name, its color and the regex, so that I can tell Patterns that share a name apart.
22. As a developer, I want to filter the list, so that a long list stays manageable.
23. As a developer, I want to add a User Pattern, so that textier detects my own kinds of pieces.
24. As a developer, I want to edit a Pattern's name, regex, Actions and color, so that I can tune it.
25. As a developer, I want to delete a User Pattern, so that I can drop one I no longer need.
26. As a developer, I want to duplicate a Preset into a User Pattern, so that I can start from something that works.
27. As a developer, I want to edit a Preset and restore its default later, so that experimenting is safe.
28. As a developer, I want Built-in Patterns to offer only on/off, so that I can't break JSON detection.
29. As a developer, I want a test box under the regex, pre-filled with the Panel's current Input, so that I test against the text I actually care about.
30. As a developer, I want the test box to highlight the Pattern's Matches as I type, so that I see at once whether my regex works.
31. As a developer, I want to see the Fields of the Match I select in the test box, so that I can check my named captures.
32. As a developer, I want a compile error shown under the regex, naming the problem, so that I know what to fix.

### Shared Pattern names

33. As a developer, I want several Patterns to share a name (`numeric` for a float and an integer Pattern), so that related pieces land in one Inspector group.
34. As a developer, I want Patterns that share a name to share one color, so that a group looks like one group.
35. As a developer, I want each Match to keep the Actions of the Pattern that found it, so that a shared name doesn't lose a Pattern's Actions.
36. As a developer, I want the names `json` and `escaped-json` kept for the Built-in Patterns, so that a User Pattern can't pretend to be JSON.
37. As a developer, I want overlaps between same-name Patterns resolved like any others (longest wins, then order), so that `3.14` is one `numeric` Match.

### Perl-style regex

38. As a developer, I want to write Patterns in Perl-style regex, so that what I know from Perl, PCRE, Python and PHP works.
39. As a developer, I want `(?P<name>…)`, `(?'name'…)` and `(?P=name)` accepted, so that regexes pasted from Python and PHP work.
40. As a developer, I want an unsupported construct (`\K`, recursion, conditionals, branch reset, backtracking verbs, unbounded lookbehind) to be an error naming it, so that no regex silently means something other than what I wrote.
41. As a developer, I want Field names like `client_ip` accepted, so that I'm not limited to letters and digits.

### Grok

42. As a developer, I want `%{NAME}` in a Pattern's regex to expand a Grok Definition, so that I can compose Patterns from known pieces.
43. As a developer, I want the bundled Grok Definitions to have StreamSets' names (`TIMESTAMP_ISO8601`, `LOGLEVEL`, `IPV4`, `JAVACLASS`, …), so that names I know work.
44. As a developer, I want to browse the bundled definitions as one list, with their regex, so that I can find the one I need.
45. As a developer, I want to add my own Grok Definitions, so that I can name pieces my logs repeat.
46. As a developer, I want to paste `NAME regex` lines from Logstash or StreamSets into Settings, so that I can bring my existing definitions over.
47. As a developer, I want my own definition to replace a bundled one of the same name everywhere, and to be marked as overriding it, so that I can fix a bundled definition for my logs.
48. As a developer, I want definitions to reference other definitions, so that I can build big ones from small ones.
49. As a developer, I want an unknown `%{NAME}` to be an error naming it, so that a typo is obvious.
50. As a developer, I want a definition that refers back to itself to be an error naming the loop, so that it can't hang textier.
51. As a developer, I want `\%{` to stay literal, so that I can match the text `%{`.
52. As a developer, I want "New Pattern from this" on a Grok Definition, so that I can go from the library to a highlighted Pattern in one step.

### Fields

53. As a developer, I want named captures (`%{IP:client}`, `(?<client>…)`) shown as rows in the Match's parsed view, so that I can read a log line's parts.
54. As a developer, I want the rows in regex order, so that they read like the line.
55. As a developer, I want unnamed groups and `%{IP}` without a name to give no Field, so that only what I named shows.
56. As a developer, I want a named group that didn't take part in a Match left out, so that I don't see empty rows.
57. As a developer, I want a Field name used twice to give two rows, so that nothing is hidden.
58. As a developer, I want `%{NUMBER:ms:int}` accepted, with the type shown in the label, so that pasted grok works and I can see the type was read.
59. As a developer, I want a Field row to copy its value on click, like the other parsed views, so that I can take one part out of a line.
60. As a developer, I want a Field value that is a URL or a file path to offer its Actions, so that I can open it straight from the row.
61. As a developer, I want Fields shown above a Match's own parsed view (URL parts, datetime conversions, …), so that both are there when a Pattern has both.
62. As a developer, I want Fields in Match Windows too, so that a popped-out Match looks the same.

## Implementation Decisions

Vocabulary follows `CONTEXT.md` (Grok Definition, Field, Settings, shared Pattern names added in this round). ADR-0002 (own JSON parser) and ADR-0004 (Perl-style regex on ICU) apply.

### TextierCore: compiling a regex (new seam)

- One public step turns a regex Pattern's source plus the Grok Definitions into a compiled regex, or into an error that names the cause. Config loading, `detect` and Settings all use it, so a Pattern is valid in exactly one sense everywhere.
- Rewrites, in order: `%{NAME}`, `%{NAME:field}` and `%{NAME:field:type}` expand recursively (an escaped `\%{` stays literal; an unknown name or a reference loop is an error naming it); `(?P<n>…)`, `(?'n'…)` and `(?P=n)` become ICU's spellings; every named group gets an internal name (ICU only accepts `[A-Za-z][A-Za-z0-9]*`), with a table from internal names back to the names as written, and their `:type` when grok gave one.
- Rejected with an error naming the construct, before ICU sees it: `\K` (which ICU otherwise reads as a literal K), recursion and subroutines (`(?R)`, `(?1)`, `(?&n)`), conditionals, branch reset, backtracking verbs, `(?^…)`. ICU's own compile errors (unbounded lookbehind, `\b{wb}`, …) are reported with ICU's position where possible.
- The compiled form carries the regex and its Fields' written names, in group order. Compiling happens once per Config, not on every detection pass (today `detect` recompiles each regex on every pass).

### TextierCore: Grok Definitions

- A Grok Definition is a name and a regex body; it is not a Pattern.
- The bundled library is StreamSets' 69 names as one flat list, with bodies from Logstash's `logstash-patterns-core` `legacy` set (Apache-2.0; the NOTICE ships with textier), `HOST` defined as `%{HOSTNAME}`. Oniguruma-only syntax in the bodies (`\h` meaning a hex digit, Ruby's `(?m)`, a bare `{`) is fixed when the library is written, so each body means in ICU what it means in Logstash. It's embedded as source, like the bundled themes, because the app bundle is built from the bare binary.
- The user's own definitions live in the config file, in a `grok` object mapping names to regex bodies. A user definition replaces a bundled one of the same name everywhere, including inside other bundled definitions.

### TextierCore: Config and the config file

- The config file gains the `grok` object. `ConfigFile.encode` writes it (after `patterns`, in the documented key order), and `load` reads it; a bad definition is a warning naming it, and Patterns that reference it are skipped with a warning.
- A regex Pattern's validity now depends on the Config's Grok Definitions, so `load` checks Patterns with the compile step against the loaded definitions. Warnings name the cause (`\K isn't supported`, `unknown grok definition NOPE`, `grok definitions loop: A → B → A`) instead of "invalid regex".
- A Pattern named `json` or `escaped-json` that isn't the matching Built-in Pattern is skipped with a warning.
- Shared names: the color of a name is the color of the first Pattern with that name (its `color`, or its palette default); the palette hands out user-Pattern colors per name, not per Pattern.

### TextierCore: detection and inspection

- A Match records which Pattern found it (its index in the Config is enough), so details, Match Windows and the Input's JSON click stop looking Patterns up by name. Its Actions are that Pattern's.
- A Match of a regex Pattern carries its Fields: name as written, type when grok gave one, value and UTF-16 range in the Input, in group order, one per capture that took part in the Match.
- `Detail` gains the Fields of a regex Match alongside its existing parsed form (URL, datetime, file path or text), so the Inspector shows the Fields rows first, then the parsed view. A Field value that's a URL or file path Match in its entirety (`stringValueMatch`) offers that Match's Actions.
- The Inspector's grouping by name is unchanged in shape (tabs are keyed by name); its color is the name's color.

### Textier app: Settings

- A `SettingsModel` (observable, like `PanelModel`) owns the window's state: a draft per edited value, which values are invalid and why, and the warnings by section. It writes through `ConfigFile.encode` to the config store's file and follows the store's reloads. Every valid edit writes; an invalid one stays a draft.
- On a reload from outside, the model takes the file's values and keeps any invalid draft on top, flagged "the file changed".
- Sections: General (shortcut recorder, editor command with a Test button that runs it on the config file itself, Copy JSON, Inspector layout), Appearance (light and dark theme files with a file picker), Patterns (the ordered list and the Pattern editor with its test box), Grok Definitions (bundled list, user definitions, paste `NAME regex` lines, New Pattern from this).
- The Pattern editor's test box starts with the Panel's current Input and shows the draft Pattern's Matches (run with the draft compiled against the current Grok Definitions) and the Fields of the selected Match.
- "Restore default" on a Preset puts back the shipped regex, Actions and color; it shows only while the Preset differs from them. Duplicate makes a User Pattern with the same values and a name the user edits.
- "New Pattern from this" adds a User Pattern named after the definition, lowercased with `_` as spaces, with the regex `%{NAME}` and Actions `copy`.
- The menu bar gains "Settings…" (⌘,) and loses "Reload Config"; ⌘, in the Panel opens Settings too.

## Testing Decisions

- Tests drive public seams with realistic text, as in v1–v3; the Laravel/Monolog line stays the canonical fixture, joined by a few real-world log lines that grok is good at (an nginx access line, a Java log line with a stack frame).
- **Compile step** (new seam): each rewrite (grok expansion with nesting, overrides and `\%{`; the Perl named-group spellings; Field names ICU can't take, including `[client][ip]` and repeats; `:type`) and each rejection by name (`\K`, `(?R)`, `(?1)`, conditionals, branch reset, verbs, `(?^)`, an unknown `%{NAME}`, a loop). The bundled library: all 69 StreamSets names are present and every definition compiles on its own.
- **`detect` / `inspect`** (existing seam): grok Patterns match where expected; Fields come out in order, with repeats, skipped optional groups and type labels; Field values that are URLs or paths carry Actions; shared names give one group and one color; a Match keeps its own Pattern's Actions when two Patterns share a name; longest-wins holds across same-name Patterns.
- **`ConfigFile.load` / `encode`** (existing seam): the `grok` key round-trips; warnings name the cause; reserved names are refused.
- **App tests** (`Tests/TextierAppTests`, through `AppHarness`): `SettingsModel` edits write the file and the Panel follows; invalid drafts aren't written; an outside edit reloads the model and keeps an invalid draft; reorder, toggle, add, delete, duplicate, Restore default and New Pattern from this; warnings by section; the test box's Matches and Fields for a draft. The Inspector and Match Windows show Field rows, and a Match Window keeps the right Actions for a shared name. SwiftUI views are driven through the model, as in v2/v3.
- Prior art: `JSONDetectionTests`, `OverlapAndNestingTests`, `ConfigFileTests`, `InspectionTests`, `FileLinePairingTests`, `AppTests` (`PanelModel` via `AppHarness`).

## Out of Scope

- PCRE2 or any engine other than ICU (ADR-0004); recursion, conditionals, `\K` and the rest stay unsupported.
- StreamSets/Java regex compatibility beyond what ICU shares with it.
- Type conversion of Fields (`:int`, `:float` are labels only).
- Logstash's full `legacy` set, the `ecs-v1` set, categories in the library, and loading pattern files from disk.
- A `description` per Pattern; Fields in the Inspector's list previews.
- Storing settings anywhere other than the config file; import/export.
- Comments in the config file.

## Further Notes

- The done scenario: open Settings with ⌘,, add a Pattern named `access` with `%{IPV4:client} - - \[%{HTTPDATE:time}\] "%{WORD:method} %{URIPATHPARAM:path}`, see the nginx line in the test box highlight with four Fields, switch to the Panel and find the `access` tab with those Fields as rows; clicking `client` copies the address.
- A request path such as `/api/v1/signin` is also a file path Match by the current Preset, so its Field row offers Open in Editor. That's the existing file path rule, not something v4 changes.
- Grok research (2026-10-09): 312 of Logstash's 317 `legacy` definitions compile in ICU once expanded with renamed captures. The five that don't use a bare `{` or `.?*`; three more compile but mean something else (`\h` as a hex digit, Ruby's `(?m)`, `[[:alnum:]]`). The library fix-ups above cover the ones among StreamSets' 69.
- ICU checks (2026-10-09): `(?P<n>…)`, `(?'n'…)`, `(?P=n)`, `(?R)`, `(?1)`, conditionals, branch reset, verbs, `(?<=a+)`, `(?^…)` and `\b{wb}` fail to compile; `\K` compiles but matches a literal `K`.
