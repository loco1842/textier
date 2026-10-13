# textier

A macOS menu bar tool for developers: paste plain text, and textier detects the structured pieces inside it (timestamps, JSON, URLs, file paths, …) and makes each one actionable.

## Language

**Input**:
The raw plain text in the Panel: typed or pasted there, or opened from the Selection Popover.
_Avoid_: Source, content, payload

**Pattern**:
A rule that detects one kind of structured piece in the Input. Every Pattern is one of the three kinds below. A Pattern's name is the kind of piece it detects, and several Patterns can share one (a float and an integer Pattern both named `numeric`): they show as one group in the Inspector, in one color.
_Avoid_: Rule, detector, matcher

**Glyph**:
The small symbol that marks a Pattern name wherever the name appears, beside its color (`{}` for JSON, a clock for datetime). Built-in Patterns and Presets each have their own; User Patterns share one.
_Avoid_: Icon, badge

**Built-in Pattern**:
A Pattern implemented in code because a regex can't express it (JSON object, for example). The user can enable or disable it but not edit it.
_Avoid_: Structural pattern, native pattern

**Preset**:
A regex Pattern that ships with textier (datetime, URL, file path, log level, …). Some Presets are enabled by default; the user can toggle, copy or edit them. The first regex Pattern with a Preset's name is that Preset; another sharing its name is a User Pattern in its group.
_Avoid_: Default pattern, sample pattern

**User Pattern**:
A regex Pattern the user wrote themselves in the config file.
_Avoid_: Custom pattern

**Grok Definition**:
A named regex fragment (`IP`, `TIMESTAMP_ISO8601`) that a Pattern's regex can reference as `%{NAME}`. Some ship with textier; the user can add their own. It is not a Pattern: it never matches on its own, has no Actions and has no place in the Inspector.
_Avoid_: Grok pattern, sub-pattern, macro

**Field**:
A named capture in a Pattern's regex (`%{IP:client}` or `(?<client>…)`): a labelled part of each Match, shown in the Match's parsed view.
_Avoid_: Capture, group, attribute

**Match**:
One region of the Input that a Pattern detected. A Match is highlighted and offers Actions. In the text a click is a plain text click; ⌘-click (the modifier can be changed) on a Match selects it in the Inspector.
_Avoid_: Segment, token, hit, highlight

**Color Rule**:
Part of a Pattern: a regex and a color. A Match whose text the regex finds (ignoring case) is drawn in that color instead of its Pattern's; a Pattern's rules are tried in order. The log level Preset ships with rules by severity (errors red, warnings yellow); any Pattern can have them (HTTP statuses by class, environments by stage).
_Avoid_: Value color, severity color

**Summary**:
One line saying what a Match means, taken from its parsed view: a datetime's local time and age, a file path's file and line, a JSON object's keys, a regex Pattern's first Fields. A Match whose Summary would only repeat its text has none.
_Avoid_: Preview, description

**Plain Text**:
The parts of the Input not covered by any top-level Match. It is not a Pattern: nothing detects it, and it can't be configured or disabled.
_Avoid_: Text pattern, leftover, unmatched text

**Action**:
Something the user can do with a Match: copy it, beautify it, open it in a Match Window, and so on.
_Avoid_: Command, operation

## Surfaces

**Panel**:
textier's main window, for longer work on a text, opened from the Selection Popover (or by the shortcut when the menu bar icon is out of sight): a regular window with close, minimize and full screen buttons. It holds the editable Input, with its Matches highlighted, beside the Inspector. It takes an Input of up to 100 MB; a bigger one is refused, and the Input stays as it was. Go to Line (⌘G) moves the cursor to a line, or a line and column, of the Input.
_Avoid_: Popover, input window, main panel

**Selection Popover**:
What the global shortcut opens under textier's menu bar icon, for quick work on the text selected in the app in front (copied with a simulated ⌘C, the clipboard put back after): its first lines unwrapped with their Matches highlighted, above one collapsible list of the Matches, filtered by Pattern or not (its chips keep the Panel's tab order; a last chip lists the Plain Text between them). A click on a row selects it and opens it on its parsed view, the Inspector's card (JSON beautified, Tree a click away), one row at a time; its buttons (Copy, Pop Out, …) run its Actions. Its text can be edited, or typed or pasted in by hand. It never reads the clipboard; with nothing selected it says so. The menu bar icon opens it again with the last selection, until Clear empties it (or, when Settings says so, it clears itself a set time after closing). Deeper work is a Pop Out, or the Panel, which it opens the text in (or as it was, with no text). A right-click on the menu bar icon shows a menu: Show Selection, Open Panel, Clear Selection, Settings, the config file, Quit.
_Avoid_: Clipboard Popover, menu, menu bar window, mini Panel

**Inspector**:
The side of the Panel that lists every Match in the Input, nested ones included, grouped by Pattern name (one tab per name, or one list with a collapsible section per name), and shows the selected Match parsed. Each group lists its Matches in the order they come in the Input, or sorted by value: a datetime by the instant it means (earliest or latest first), a file path by path then line, anything else by its text (A→Z or Z→A, numbers as numbers). A sort lasts until new text comes in (a capture, a paste over everything); edits keep it. Plain Text keeps its order.
_Avoid_: Right panel, detail pane, sidebar, match list

**Match Window**:
An Inspector view of one Match, popped out into a window of its own so it can stay open beside others. Many can be open at once. Its Raw view is an editable scratch copy of the Match's text (JSON beautified at first); View Original puts back the text as it is in the Input.
_Avoid_: Detail window, child window, viewer window, pop-out

**Settings**:
The window for changing what the config file holds: the shortcuts (the global one, and each command's in the app), the editor, appearance, the Patterns and the Grok Definitions. The config file stays the source of truth, so editing it by hand still works.
_Avoid_: Preferences, config UI, options

**JSON Viewer**:
The interactive tree the Inspector (or a Match Window) shows for a JSON Match: nested values expand and collapse, and each key or value has its own Actions.
_Avoid_: JSON tree
