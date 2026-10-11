# 05: Settings window: General and Appearance

**What to build:** A Settings window opens from the menu bar ("Settings…", ⌘,) and with ⌘, in the Panel; "Open Config File" stays and "Reload Config" goes. It edits the config file, which stays the source of truth: every valid change saves at once and the Panel follows; an invalid value is shown inline and not saved. When the file changes on disk, the window reloads, keeping an invalid draft on top with a note that the file changed. Config warnings show in the section they belong to. This ticket brings the window with its General section (shortcut recorder with a note when it can't be registered, editor command with a Test button that opens the config file, Copy JSON, Inspector layout) and its Appearance section (light and dark theme files, with a file picker).

Spec: `.scratch/textier-v4/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] ⌘, in the Panel and "Settings…" in the menu bar open one Settings window
- [x] Recording ⌃⌥Y as the shortcut writes it to the config file and the hot key follows; one that can't be registered says so
- [x] Changing Copy JSON or the Inspector layout writes the file and the Panel follows
- [x] An editor command that won't run shows the warning in General after Test
- [x] Saving the config file in an editor while Settings is open updates the window; a broken draft survives with a "file changed" note
- [x] A bad theme path shows its warning in Appearance
- [x] App tests drive a `SettingsModel` through `AppHarness`: edits write the file, invalid drafts don't, outside edits reload, warnings land in their section

## Comments

**2026-10-09, closed without the manual pass:** Implemented and committed on master (v4 commits 5e60b94..60ba734); the full suite passes and the acceptance criteria are covered by `Tests/TextierCoreTests` and `Tests/TextierAppTests`. The user closed it without running `.scratch/textier-v4/manual-test.txt`, which is kept for whenever the SwiftUI controls, menu bar and layout get a look by hand.
