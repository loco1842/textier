<p align="center">
  <img src="docs/assets/icon.png" width="128" alt="textier icon">
</p>

<h1 align="center">textier</h1>

<p align="center">
  <b>Select text anywhere. Press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd>. Every timestamp, JSON blob, URL and file path in it becomes something you can act on.</b>
</p>

<p align="center">
  A native macOS menu bar tool for developers who live in logs, stack traces and API responses.
</p>

<p align="center">
  <img src="docs/demo/demo.gif" width="860" alt="textier demo: a log selection opens in the Selection Popover, then in the Panel with its JSON queried by JSONPath">
  <br>
  <sub><a href="docs/demo/demo.mp4">Watch the demo in full quality (MP4)</a></sub>
</p>

---

## Why

A log line like this is dense with things you want to *do* something with:

```
2026-10-11 09:41:07 ERROR checkout.payment: charge failed {"order":"ORD-10293","gateway":{"status":502}} see /srv/shop/app/Payments/Gateway.php:118
```

When was that in local time, and how long ago? What's in that JSON? Can you jump to line 118? Usually that means a JSON formatter tab, a timestamp converter and a path you copy by hand. textier does all of it in place: it finds the structured pieces in plain text, highlights them, and gives each one the right actions.

## Features

### Selection Popover: one shortcut, from any app

- Select text in any app (terminal, browser, Slack, your editor) and press **⌃⌥T**. The popover opens under textier's menu bar icon.
- Shows the first lines of your selection, with every Match highlighted.
- Lists every Match in a collapsible list. Click a row to open it on its parsed view in place: a datetime's local time and age, JSON beautified, a file path's line.
- Filter the list by Pattern with one click. The chips are draggable, and keep the same order as the Panel's tabs.
- Copy, Pop Out or open in your editor right from the row.
- Edit the text, or paste something new in by hand. **Clear** empties it, or have it clear itself a while after the popover closes (Settings → General).
- Right-click the menu bar icon for Show Selection, Open Panel, Clear Selection, Settings and Quit.
- **It never reads your clipboard.** textier copies the selection with a simulated ⌘C and puts your clipboard back afterwards.

### The Panel: for longer work on a text

- An editable Input with Matches highlighted, line numbers and Wrap Lines. Clicks are plain text clicks; **⌘-click** a Match to inspect it. **⌘G** goes to a line (or `line:column`).
- Beside it the **Inspector**: every Match, nested ones included, grouped by Pattern in tabs or in one list (**⌘L**). Sort any Pattern's Matches by value (datetimes earliest or latest first, everything else A → Z, numbers as numbers) or keep them in text order.
- **⌘1–⌘9** switch tabs, **⌘E** toggles highlighting, **⌘⇧P** pops the selected Match out into its own **Match Window**. You can keep many Match Windows open side by side; their Raw view opens JSON beautified, to edit as a scratch copy, with **View Original** a click away.

### A JSON Viewer that understands JSON

- A **Tree** with expand and collapse, or **Raw**: beautified, syntax-colored, with line numbers.
- **Filter** by key or value, or query with **JSONPath**: `$.items[?@.qty > 1].sku`. A mistake points at where the query went wrong.
- Copy Results, Copy Beautified, and a path bar for the selected node.
- JSON escaped inside a JSON string is detected too, and opens as JSON.

### Built-in Patterns

| Pattern | Detects | Actions |
|---|---|---|
| `json` | JSON objects and arrays anywhere in the text | Pop Out, Copy Beautified, Copy |
| `datetime` | ISO 8601 / `YYYY-MM-DD HH:MM:SS`, 10- and 13-digit Unix epochs | Copy, with UTC, local, epoch and relative time |
| `url` | `http`/`https` URLs, without the sentence's trailing punctuation | Open in Browser, Copy |
| `file path` | `/abs/path` and `~/path`, with an optional `:line[:col]` | Open in Editor (at the line), Copy |
| `log level` | `ERROR`, `WARNING`, `INFO`, `DEBUG`… in any case (off by default) | Copy, colored by severity |

### Make it yours

- **Your own Patterns**: any regex, with named captures becoming **Fields** in the parsed view.
- **Grok**: write `%{IP:client} %{WORD:method}` using the bundled [logstash](https://github.com/logstash-plugins/logstash-patterns-core) Grok Definitions, or add your own.
- **Color Rules**: color a Match by its value. Errors red and warnings yellow, HTTP 5xx red and 4xx orange.
- **Settings** has a live test box for every Pattern. Behind it, a plain JSON config file at `~/.config/textier/config.json` stays the source of truth: edit it by hand and textier reloads it.
- **Your editor**: `cursor`, `code`, `zed` and `subl` open at the line. A command template like `idea --line {line} {path}` works too, and so does `$EDITOR`.

### Fast, local, private

- 100% native Swift and AppKit/SwiftUI, with no web views and no network calls.
- Each Pattern gets a time limit, so a runaway regex can't hang the app.
- Large inputs (200k+ characters) are inspected in the background.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 or later, only to build from source

## Install

### Download

1. Get the latest `textier-x.y.z.dmg` (or `.zip`) from the [Releases page](https://github.com/loco1842/textier/releases/latest). It runs on both Apple silicon and Intel Macs.
2. Drag **Textier** to **Applications**.
3. textier isn't signed with an Apple Developer ID, so macOS quarantines it and refuses to open it ("can't be opened" / "is damaged"). Clear the quarantine flag once:

   ```bash
   xattr -d com.apple.quarantine /Applications/Textier.app
   ```

4. Open it. textier lives in the menu bar, with no Dock icon.

### Build from source

```bash
git clone https://github.com/loco1842/textier.git
cd textier
scripts/bundle.sh          # builds build/Textier.app (release, ad-hoc signed)
open build/Textier.app
```

A build of your own isn't quarantined, so it needs no `xattr`.

### Accessibility permission

To copy your selection, textier sends ⌘C to the app in front, which macOS allows only with Accessibility. The first time you press the shortcut, grant it in **System Settings → Privacy & Security → Accessibility**. The app is ad-hoc signed, so macOS asks again after each update or rebuild: remove the old textier entry from the list, and add the new one.

## Usage

| | |
|---|---|
| **⌃⌥T** | Open the Selection Popover with the selected text (changeable in Settings) |
| Click the menu bar icon | Reopen the popover with the last selection |
| Right-click the menu bar icon | Show Selection, Open Panel, Clear Selection, Settings…, Quit |
| **↑ ↓**, **→ ←**, **Space**, **Return** | Move through the Matches, open or close a row, run its first Action |
| **Esc** | Close the popover or hide the Panel |
| **⌘-click** a Match | Inspect it (a plain click just places the cursor) |
| **⌘G** | Go to a line, or `line:column`, in the Panel or a Match Window's Raw editor |
| **⌘L** / **⌘E** / **⌘1–9** / **⌘⇧P** | Panel: list layout / highlighting / switch tab / Pop Out |
| **⌘,** / **⌘Q** | Settings / Quit |

Every shortcut, and the ⌘ of ⌘-click and ⌘1–9, can be changed in **Settings → Shortcuts**.

### Config file

`~/.config/textier/config.json` is written on first launch with the defaults. A trimmed example:

```json
{
  "shortcut": "ctrl+option+t",
  "editorCommand": "",
  "appearance": "system",
  "clearSelectionAfter": 0,
  "shortcuts": { "goToLine": "cmd+g", "toggleWrapLines": "cmd+option+w", "matchClick": "cmd", "…": "…" },
  "patterns": [
    { "name": "json", "builtin": "json", "enabled": true, "actions": ["open", "copy-pretty", "copy"] },
    { "name": "ticket", "regex": "%{MYTICKET:key}", "actions": ["copy"], "color": { "light": "#9a6700", "dark": "#e3b341" } },
    { "name": "status", "regex": "\\b[1-5]\\d\\d\\b", "actions": ["copy"],
      "colors": [{ "when": "^5", "color": "#e5484d" }, { "when": "^4", "color": "#ef5f00" }] }
  ],
  "grok": { "MYTICKET": "[A-Z]+-\\d+" }
}
```

- Patterns are tried in order; when two overlap, the earlier wins.
- The first Action listed is what Return or a double-click runs.
- `clearSelectionAfter` clears the Selection Popover's text that many seconds after it closes; `0` keeps it.
- A broken entry is skipped with a warning, shown in Settings and as a ⚠︎ on the menu bar icon, and the rest keep working.

## Project layout

```
Sources/TextierCore   Detection, Patterns, Grok, the JSON parser and JSONPath, the config file (no UI)
Sources/Textier       The app: Selection Popover, Panel, Inspector, JSON Viewer, Settings
Tests/                Core tests and in-process app tests
docs/adr/             Architecture decisions
CONTEXT.md            The glossary: what Pattern, Match, Field, Panel… mean here
```

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing and the project's vocabulary.

## License

[MIT](LICENSE) © Loocoo.

textier bundles Grok Definitions from [logstash-patterns-core](https://github.com/logstash-plugins/logstash-patterns-core), licensed under Apache 2.0. See [NOTICE-logstash-patterns-core.txt](NOTICE-logstash-patterns-core.txt).
