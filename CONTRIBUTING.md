# Contributing to textier

Thanks for helping. Bug reports, Pattern ideas and pull requests are all welcome.

## Reporting a bug or asking for a feature

Open a [GitHub issue](https://github.com/loco1842/textier/issues) and include:

- your macOS version and how you built textier (`scripts/bundle.sh`, or from Xcode)
- the text you inspected, or a made-up sample that reproduces it (**please strip anything private**)
- what you expected, and what happened instead; a screenshot helps for anything visual

For a new Pattern, the regex, a few lines it should and shouldn't match, and the Actions it should have are the most useful start.

## Building

You need macOS 26 and Xcode 26 or later. textier is a plain Swift package; there is no `.xcodeproj`.

```bash
scripts/bundle.sh        # release build, assembled into build/Textier.app
open build/Textier.app
```

The scripts select an installed Xcode on their own. The Command Line Tools alone lack the macro plugins SwiftUI and Swift Testing need, and switching `xcode-select` needs `sudo`.

Each rebuild is ad-hoc signed afresh, so macOS asks for Accessibility again: remove textier from **System Settings → Privacy & Security → Accessibility** and add the new build.

You can also open `Package.swift` in Xcode and run the `Textier` scheme.

## Testing

Run the tests with **`scripts/test.sh`**. Plain `swift test` fails for the reason above. Arguments go through to `swift test`:

```bash
scripts/test.sh                              # everything (the app tests take about a minute)
scripts/test.sh --skip TextierAppTests       # core only, under a second once built
scripts/test.sh --filter SelectionPopoverTests
```

- `TextierCoreTests` cover detection, Patterns, Grok, the JSON parser, JSONPath and the config file.
- `TextierAppTests` run the real app in-process. Before writing one, read [`docs/agents/testing.md`](docs/agents/testing.md): AppKit has several traps there (run-loop timers rather than `Task.sleep`, no `NSApp.activate()` in app code, and more) that the harness works around.
- New behavior comes with a test. A UI change that tests can't see (drag and drop, how something looks) gets a step in the manual test list.

### Recording the demo

`scripts/make-demo.sh` captures the README demo from the real app and assembles `docs/demo/demo.gif` and `demo.mp4`. It takes the screen for about 20 seconds and needs Screen Recording permission for your terminal.

## Code and words

- **Read [`CONTEXT.md`](CONTEXT.md) first.** It's the glossary: what a *Pattern*, *Match*, *Field*, *Preset*, *Panel* and *Selection Popover* are, and the words to avoid for each. Code, comments, UI text and docs all use these words.
- Architecture decisions live in [`docs/adr/`](docs/adr/): why a native Swift app, why a hand-written JSON parser, why native syntax coloring, why ICU regex. Please open an issue before going against one.
- Match the surrounding code: Swift 6 strict concurrency, AppKit where SwiftUI falls short, and comments that say *why*.
- textier makes no network calls and never reads the clipboard on its own. Changes need to keep it that way.

## Pull requests

1. Fork, and branch from `main`.
2. Keep the change focused; one feature or fix per PR.
3. Make sure `scripts/test.sh` passes.
4. Describe what changed and how you checked it. For UI changes, add a screenshot.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
