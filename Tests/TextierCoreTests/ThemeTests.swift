import Foundation
import Testing
import TextierCore

@Suite("Theme")
struct ThemeTests {
    func load(_ text: String) throws(ThemeError) -> Theme {
        try Theme.load(Data(text.utf8))
    }

    // MARK: Bundled themes

    @Test func githubLightResolvesTheColorsVSCodeShowsForJSON() {
        let theme = Theme.githubLight

        #expect(theme.name == "GitHub Light Default")
        #expect(theme.foreground == "#1f2328")
        #expect(theme.background == "#ffffff")
        #expect(theme.style(for: .key) == TokenStyle(color: "#116329"))
        #expect(theme.style(for: .string) == TokenStyle(color: "#0a3069"))
        #expect(theme.style(for: .number) == TokenStyle(color: "#0550ae"))
        #expect(theme.style(for: .boolean) == TokenStyle(color: "#0550ae"))
        #expect(theme.style(for: .null) == TokenStyle(color: "#0550ae"))
        #expect(theme.style(for: .punctuation) == TokenStyle(color: "#1f2328"))
    }

    @Test func githubDarkResolvesTheColorsVSCodeShowsForJSON() {
        let theme = Theme.githubDark

        #expect(theme.name == "GitHub Dark Default")
        #expect(theme.foreground == "#e6edf3")
        #expect(theme.background == "#0d1117")
        #expect(theme.style(for: .key) == TokenStyle(color: "#7ee787"))
        #expect(theme.style(for: .string) == TokenStyle(color: "#a5d6ff"))
        #expect(theme.style(for: .number) == TokenStyle(color: "#79c0ff"))
        #expect(theme.style(for: .null) == TokenStyle(color: "#79c0ff"))
        #expect(theme.style(for: .punctuation) == TokenStyle(color: "#e6edf3"))
    }

    // MARK: Scope rules

    /// A small theme in the shape VS Code themes take: editor colors, a rule with
    /// no scope for defaults, and scope rules as strings, lists and comma lists.
    let minimal = #"""
    {
      "name": "Minimal",
      "type": "dark",
      "colors": { "editor.foreground": "#cccccc", "editor.background": "#1e1e1e" },
      "tokenColors": [
        { "settings": { "foreground": "#d4d4d4" } },
        { "scope": "string", "settings": { "foreground": "#ce9178" } },
        { "scope": ["constant.numeric", "constant.language"], "settings": { "foreground": "#b5cea8" } },
        { "scope": "support.type.property-name, punctuation", "settings": { "foreground": "#9cdcfe", "fontStyle": "bold" } }
      ]
    }
    """#

    @Test func scopeRulesAsStringsListsAndCommaListsAllApply() throws {
        let theme = try load(minimal)

        #expect(theme.name == "Minimal")
        #expect(theme.foreground == "#cccccc")
        #expect(theme.background == "#1e1e1e")
        #expect(theme.style(for: .string) == TokenStyle(color: "#ce9178"))
        #expect(theme.style(for: .number) == TokenStyle(color: "#b5cea8"))
        #expect(theme.style(for: .boolean) == TokenStyle(color: "#b5cea8"))
        #expect(theme.style(for: .key) == TokenStyle(color: "#9cdcfe", fontStyle: .bold))
        #expect(theme.style(for: .punctuation) == TokenStyle(color: "#9cdcfe", fontStyle: .bold))
    }

    @Test func aMoreSpecificScopeBeatsAGeneralOneWhateverTheOrder() throws {
        let theme = try load(#"""
        { "tokenColors": [
          { "scope": "constant.language.json", "settings": { "foreground": "#ff0000" } },
          { "scope": "constant", "settings": { "foreground": "#00ff00" } }
        ] }
        """#)

        #expect(theme.style(for: .boolean).color == "#ff0000")
        #expect(theme.style(for: .number).color == "#00ff00")
    }

    @Test func aDescendantSelectorAppliesOnlyWithItsAncestor() throws {
        let theme = try load(#"""
        { "tokenColors": [
          { "scope": "string", "settings": { "foreground": "#111111" } },
          { "scope": "meta.structure.dictionary.value.json string", "settings": { "foreground": "#222222" } },
          { "scope": "meta.structure.array.json constant", "settings": { "foreground": "#333333" } },
          { "scope": "constant", "settings": { "foreground": "#444444" } }
        ] }
        """#)

        #expect(theme.style(for: .string).color == "#222222")
        // Numbers are colored as they sit in an object value, not in an array.
        #expect(theme.style(for: .number).color == "#444444")
    }

    @Test func amongEquallySpecificRulesTheLaterWins() throws {
        let theme = try load(#"""
        { "tokenColors": [
          { "scope": "string", "settings": { "foreground": "#111111", "fontStyle": "italic" } },
          { "scope": "string", "settings": { "foreground": "#222222" } }
        ] }
        """#)

        #expect(theme.style(for: .string) == TokenStyle(color: "#222222", fontStyle: .italic))
    }

    /// A key is a `string.json` too: it takes the string color unless something
    /// names the property-name scope, as in VS Code.
    @Test func keysInheritTheStringColorUntilAPropertyNameRuleOverridesIt() throws {
        let plain = try load(##"{ "tokenColors": [{ "scope": "string", "settings": { "foreground": "#111111" } }] }"##)
        #expect(plain.style(for: .key).color == "#111111")

        let named = try load(#"""
        { "tokenColors": [
          { "scope": "support.type.property-name", "settings": { "foreground": "#222222" } },
          { "scope": "string", "settings": { "foreground": "#111111", "fontStyle": "underline" } }
        ] }
        """#)
        #expect(named.style(for: .key) == TokenStyle(color: "#222222", fontStyle: .underline))
    }

    @Test func anEmptyFontStyleClearsAnInheritedOne() throws {
        let theme = try load(#"""
        { "tokenColors": [
          { "scope": "string", "settings": { "fontStyle": "italic bold" } },
          { "scope": "support.type.property-name", "settings": { "fontStyle": "" } }
        ] }
        """#)

        #expect(theme.style(for: .string).fontStyle == [.italic, .bold])
        #expect(theme.style(for: .key).fontStyle == [])
    }

    @Test func shortHexColorsAreExpandedAndUppercaseIsLowered() throws {
        let theme = try load(#"""
        { "colors": { "editor.foreground": "#ABC", "editor.background": "#FFFFFF80" },
          "tokenColors": [{ "scope": "string", "settings": { "foreground": "#abcd" } }] }
        """#)

        #expect(theme.foreground == "#aabbcc")
        #expect(theme.background == "#ffffff80")
        #expect(theme.style(for: .string).color == "#aabbccdd")
    }

    @Test func aRuleWithAnInvalidColorKeepsTheInheritedColor() throws {
        let theme = try load(#"""
        { "colors": { "editor.foreground": "#123456" },
          "tokenColors": [{ "scope": "string", "settings": { "foreground": "red", "fontStyle": "bold" } }] }
        """#)

        #expect(theme.style(for: .string) == TokenStyle(color: "#123456", fontStyle: .bold))
    }

    @Test func withoutEditorColorsTheDefaultsFollowTheThemeType() throws {
        let dark = try load(#"{ "type": "dark", "tokenColors": [] }"#)
        let light = try load(#"{ "tokenColors": [] }"#)

        #expect(dark.foreground == "#d4d4d4")
        #expect(dark.background == "#1e1e1e")
        #expect(light.foreground == "#000000")
        #expect(light.background == "#ffffff")
        #expect(light.style(for: .string).color == "#000000")
    }

    // MARK: JSONC

    @Test func commentsAndTrailingCommasAreTolerated() throws {
        let theme = try load(#"""
        // A theme as VS Code saves it.
        {
          "name": "Commented", /* inline */
          "colors": {
            "editor.foreground": "#cccccc", // trailing comment
          },
          "tokenColors": [
            {
              "scope": "string",
              "settings": { "foreground": "#ce9178", },
            },
          ],
        }
        """#)

        #expect(theme.name == "Commented")
        #expect(theme.style(for: .string).color == "#ce9178")
    }

    @Test func commentMarkersAndCommasInsideStringsAreKept() throws {
        let theme = try load(#"""
        { "name": "a // b /* c */ ,]", "tokenColors": [] }
        """#)

        #expect(theme.name == "a // b /* c */ ,]")
    }

    // MARK: Rejection

    @Test(arguments: [
        "", "not json", "[]", #""theme""#, "{", #"{ "name": "Nothing" }"#,
        #"{ "tokenColors": "./theme.tmTheme" }"#, "{ /* unterminated ",
    ])
    func malformedThemesAreRejected(text: String) {
        #expect(throws: ThemeError.self) { try load(text) }
    }

    @Test func aRejectionSaysWhy() {
        #expect {
            try load(#"{ "name": "Nothing" }"#)
        } throws: { error in
            (error as? ThemeError)?.message.contains("tokenColors") == true
        }
    }
}
