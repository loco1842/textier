import Testing
import TextierCore

@Suite("Editor command resolution")
struct EditorCommandTests {
    let path = "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php"

    // MARK: Default

    @Test func withNothingConfiguredItOpensCursorAtTheLine() {
        #expect(EditorCommand.arguments(template: nil, editor: nil, path: path, line: 118)
            == ["cursor", "-g", "\(path):118"])
    }

    @Test func theDefaultWithoutALineOpensJustThePath() {
        #expect(EditorCommand.arguments(template: nil, editor: nil, path: path, line: nil) == ["cursor", path])
    }

    @Test(arguments: ["", "   ", "\t\n"])
    func aBlankTemplateOrEditorCountsAsUnset(blank: String) {
        #expect(EditorCommand.arguments(template: blank, editor: blank, path: path, line: 118)
            == ["cursor", "-g", "\(path):118"])
    }

    // MARK: $EDITOR

    @Test(arguments: [
        ("cursor", ["cursor", "-g", "/a/B.php:118"]),
        ("code", ["code", "-g", "/a/B.php:118"]),
        ("zed", ["zed", "/a/B.php:118"]),
        ("subl", ["subl", "/a/B.php:118"]),
    ])
    func knownGUIEditorsGetTheirLineFlag(editor: String, expected: [String]) {
        #expect(EditorCommand.arguments(template: nil, editor: editor, path: "/a/B.php", line: 118) == expected)
    }

    @Test(arguments: ["cursor", "code", "zed", "subl"])
    func knownGUIEditorsWithoutALineGetJustThePath(editor: String) {
        #expect(EditorCommand.arguments(template: nil, editor: editor, path: "/a/B.php", line: nil) == [editor, "/a/B.php"])
    }

    @Test func flagsInEditorAreKeptAndTheEditorIsKnownByItsBasename() {
        #expect(EditorCommand.arguments(template: nil, editor: "/usr/local/bin/code --wait", path: "/a/B.php", line: 7)
            == ["/usr/local/bin/code", "--wait", "-g", "/a/B.php:7"])
    }

    @Test func anUnknownEditorGetsJustThePathEvenWithALine() {
        #expect(EditorCommand.arguments(template: nil, editor: "mate -w", path: "/a/B.php", line: 7)
            == ["mate", "-w", "/a/B.php"])
    }

    @Test(arguments: ["vi", "vim", "nvim", "/usr/bin/vim -u NONE", "nano", "emacs -nw", "hx", "micro"])
    func terminalEditorsAreSkippedForTheDefaultSinceTheyCantRunWithoutATerminal(editor: String) {
        #expect(EditorCommand.arguments(template: nil, editor: editor, path: "/a/B.php", line: 118)
            == ["cursor", "-g", "/a/B.php:118"])
    }

    // MARK: Template

    @Test func theTemplateWinsOverEditor() {
        #expect(EditorCommand.arguments(template: "zed {path}:{line}", editor: "code", path: "/a/B.php", line: 118)
            == ["zed", "/a/B.php:118"])
    }

    @Test func placeholdersAreSubstitutedWithinAndAcrossTokens() {
        let arguments = EditorCommand.arguments(
            template: "idea --line {line} {path}", editor: nil, path: "/a/B.php", line: 42
        )

        #expect(arguments == ["idea", "--line", "42", "/a/B.php"])
    }

    @Test func aPathWithSpacesStaysOneArgument() {
        let spaced = "/Users/mac/My Projects/app/File.php"

        #expect(EditorCommand.arguments(template: "zed {path}:{line}", editor: nil, path: spaced, line: 3)
            == ["zed", "\(spaced):3"])
        #expect(EditorCommand.arguments(template: nil, editor: "code", path: spaced, line: 3)
            == ["code", "-g", "\(spaced):3"])
    }

    @Test func quotedTemplateTokensKeepTheirSpaces() {
        let arguments = EditorCommand.arguments(
            template: #"'/Applications/My Editor.app/bin/ed' --goto "{path}:{line}""#,
            editor: nil, path: "/a/B.php", line: 9
        )

        #expect(arguments == ["/Applications/My Editor.app/bin/ed", "--goto", "/a/B.php:9"])
    }

    @Test func withoutALineTheTemplateDropsColonLine() {
        #expect(EditorCommand.arguments(template: "zed {path}:{line}", editor: nil, path: "/a/B.php", line: nil)
            == ["zed", "/a/B.php"])
    }

    @Test func withoutALineABareLineTokenGoesWithTheFlagBeforeIt() {
        #expect(EditorCommand.arguments(template: "idea --line {line} {path}", editor: nil, path: "/a/B.php", line: nil)
            == ["idea", "/a/B.php"])
        #expect(EditorCommand.arguments(template: "ed {path} {line}", editor: nil, path: "/a/B.php", line: nil)
            == ["ed", "/a/B.php"])
    }

    @Test func aTemplateWithoutAPathPlaceholderGetsThePathAppended() {
        #expect(EditorCommand.arguments(template: "open -a TextEdit", editor: nil, path: "/a/B.php", line: 1)
            == ["open", "-a", "TextEdit", "/a/B.php"])
    }
}

@Suite("File locations in file path Matches")
struct FileLocationTests {
    let home = "/Users/mac"

    @Test(arguments: [
        ("/a/b.php", "/a/b.php", nil, nil),
        ("/a/b.php:118", "/a/b.php", 118, nil),
        ("/a/b.php:118:5", "/a/b.php", 118, 5),
        ("~/x", "/Users/mac/x", nil, nil),
        ("~/src/app.swift:12", "/Users/mac/src/app.swift", 12, nil),
    ] as [(String, String, Int?, Int?)])
    func splitsThePathFromItsLineAndColumn(text: String, path: String, line: Int?, column: Int?) {
        let location = FileLocation(matchText: text, homeDirectory: home)

        #expect(location == FileLocation(path: path, line: line, column: column))
    }

    @Test func aHomeDirectoryWithATrailingSlashExpandsCleanly() {
        #expect(FileLocation(matchText: "~/x", homeDirectory: "/Users/mac/").path == "/Users/mac/x")
    }

    @Test func theMonologBacktraceFrameParses() {
        let text = "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php:118"

        let location = FileLocation(matchText: text, homeDirectory: home)
        #expect(location.line == 118)
        #expect(location.path.hasSuffix("SendLoginFromNewIPEmailToPlayer.php"))
    }
}
