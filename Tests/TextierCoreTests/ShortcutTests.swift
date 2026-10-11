import Testing
import TextierCore

@Suite("Shortcut strings")
struct ShortcutTests {
    @Test func defaultIsControlOptionT() {
        #expect(Shortcut.default.modifiers == [.control, .option])
        #expect(Shortcut.default.key == "t")
        #expect(Shortcut.default.description == "ctrl+option+t")
    }

    @Test func parsesModifiersAndKey() throws {
        let shortcut = try #require(Shortcut("cmd+shift+space"))

        #expect(shortcut.modifiers == [.command, .shift])
        #expect(shortcut.key == "space")
    }

    @Test(arguments: [
        ("ctrl+option+t", "ctrl+option+t"),
        ("Control + Alt + J", "ctrl+option+j"),
        ("opt+command+7", "option+cmd+7"),
        ("ctrl+F12", "ctrl+f12"),
    ])
    func acceptsAliasesCaseAndSpacing(string: String, canonical: String) throws {
        #expect(try #require(Shortcut(string)).description == canonical)
    }

    @Test func descriptionIsCanonicalAndParsesBack() throws {
        let shortcut = try #require(Shortcut("cmd+shift+alt+ctrl+k"))

        #expect(shortcut.description == "ctrl+option+shift+cmd+k")
        #expect(Shortcut(shortcut.description) == shortcut)
    }

    @Test(arguments: [
        "",
        "t",
        "shift+t",
        "ctrl+option",
        "ctrl+hyper+t",
        "ctrl+option+tt",
        "ctrl+option+é",
        "ctrl++t",
        "ctrl+option+f13",
    ])
    func rejectsStringsThatAreNotAShortcut(string: String) {
        #expect(Shortcut(string) == nil)
    }
}
