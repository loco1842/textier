import Testing
import TextierCore

@Suite("File path Preset detection")
struct FilePathDetectionTests {
    let config = Config(patterns: [Preset.filePath])

    @Test func monologLineFilePathsEndAtTheirClosingQuotes() {
        let root = "/Users/mac/Documents/Projects/dv/acme-store-upgraded"

        #expect(detect(Fixtures.monologLine, config: config).map(\.text) == [
            "\(root)/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php",
            "\(root)/Modules/Notification/Services/EmailTemplateService.php",
            "\(root)/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php",
            "\(root)/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php",
            "\(root)/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php",
            "\(root)/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php",
        ])
    }

    @Test func filePathMatchOffersOpenFileFirstThenCopy() throws {
        let match = try #require(detect("see /tmp/app.log", config: config).first)

        #expect(match.patternName == "file path")
        #expect(match.actions == [.openFile, .copy])
    }

    @Test(arguments: [
        ("in /path/File.php:118 here", "/path/File.php:118"),
        ("in /path/File.php:118:7 here", "/path/File.php:118:7"),
        ("open ~/.config/textier/config.json now", "~/.config/textier/config.json"),
        ("(/var/log/system.log)", "/var/log/system.log"),
        ("file=/tmp/x.txt, next", "/tmp/x.txt"),
        ("see /usr/local/bin.", "/usr/local/bin"),
        (#"msg "missing \"/etc/hosts\" file""#, "/etc/hosts"),
        ("'/opt/homebrew/etc'", "/opt/homebrew/etc"),
        ("/Users/mac/at-start.txt", "/Users/mac/at-start.txt"),
    ])
    func positives(input: String, expected: String) {
        #expect(detect(input, config: config).map(\.text) == [expected])
    }

    @Test(arguments: [
        "http://example.com/a/b",
        "and/or",
        "2026/10/07",
        "a / b",
        "// a comment",
        "~user/file",
        "relative/path/file.txt",
        "~",
        "/",
    ])
    func nearMissesAreNotMatches(input: String) {
        #expect(detect(input, config: config).isEmpty)
    }
}
