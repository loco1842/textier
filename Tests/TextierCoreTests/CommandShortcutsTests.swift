import Foundation
import Testing
@testable import TextierCore

@Suite("The app's shortcuts in the config file")
struct CommandShortcutsTests {
    func load(_ text: String) -> ConfigLoad {
        ConfigFile.load(Data(text.utf8))
    }

    @Test func theDefaultsAreWrittenInFullOnFirstLaunch() throws {
        let text = try #require(String(data: ConfigFile.encode(.default), encoding: .utf8))
        for (key, value) in [
            ("toggleHighlighting", "cmd+e"), ("switchInspectorLayout", "cmd+l"), ("popOut", "shift+cmd+p"),
            ("goToLine", "cmd+g"), ("toggleWrapLines", ""), ("settings", "cmd+,"), ("quit", "cmd+q"),
            ("selectTab", "cmd"), ("matchClick", "cmd"),
        ] {
            #expect(text.contains(#""\#(key)": "\#(value)""#), "\(key)")
        }
        #expect(try #require(load(#"{ "patterns": [] }"#).config).shortcuts == .default)
    }

    @Test func writtenShortcutsReplaceTheDefaultsAndRoundTrip() throws {
        let loaded = load(#"""
        { "patterns": [], "shortcuts": { "goToLine": "ctrl+g", "toggleHighlighting": "", "toggleWrapLines": "cmd+option+w",
          "selectTab": "option", "matchClick": "cmd+option" } }
        """#)
        let config = try #require(loaded.config)
        #expect(loaded.warnings.isEmpty)
        #expect(config.shortcuts[.goToLine] == Shortcut("ctrl+g"))
        #expect(config.shortcuts[.toggleHighlighting] == nil)
        #expect(config.shortcuts[.toggleWrapLines] == Shortcut("cmd+option+w"))
        #expect(config.shortcuts[.popOut] == Shortcut("cmd+shift+p"))
        #expect(config.shortcuts.selectTab == [.option])
        #expect(config.shortcuts.matchClick == [.command, .option])
        #expect(ConfigFile.load(ConfigFile.encode(config)) == ConfigLoad(config: config, warnings: []))
    }

    @Test func whatCantBeUsedIsWarnedAbout() throws {
        let loaded = load(#"""
        { "patterns": [], "shortcut": "ctrl+option+t", "shortcuts": {
          "goToLine": "g", "popOut": "cmd+e", "settings": "cmd+c", "quit": "ctrl+option+t",
          "selectTab": "shift", "nope": "cmd+n" } }
        """#)
        let shortcuts = try #require(loaded.config).shortcuts
        // No modifier: its default. Taken by an earlier command, for editing, or the global one: none.
        #expect(shortcuts[.goToLine] == Shortcut("cmd+g"))
        #expect(shortcuts[.popOut] == nil)
        #expect(shortcuts[.settings] == nil)
        #expect(shortcuts[.quit] == nil)
        #expect(shortcuts.selectTab == [.command])
        let messages = loaded.warnings.map(\.message)
        #expect(messages.count == 6)
        #expect(messages.contains { $0.contains("⌘E is already Toggle Highlighting") })
        #expect(messages.contains { $0.contains("⌘C is for editing text") })
        #expect(messages.contains { $0.contains(#"no command "nope""#) })
    }

    @Test func punctuationKeysAndModifiersAlone() {
        #expect(Shortcut("cmd+,")?.key == ",")
        #expect(Shortcut("cmd+,")?.symbolText == "⌘,")
        #expect(Shortcut("ctrl+shift+[")?.symbolText == "⌃⇧[")
        #expect(Shortcut.modifiers("ctrl+option") == [.control, .option])
        #expect(Shortcut.modifiers("shift") == nil)
        #expect(Shortcut.description(of: [.command, .option]) == "option+cmd")
    }

    @Test func aDigitWithTheTabModifiersIsTaken() {
        let shortcuts = CommandShortcuts.default
        #expect(shortcuts.problem(with: Shortcut("cmd+3")!, for: .goToLine, global: .default) == "⌘3 selects tab 3")
        #expect(shortcuts.problem(with: Shortcut("ctrl+3")!, for: .goToLine, global: .default) == nil)
    }
}
