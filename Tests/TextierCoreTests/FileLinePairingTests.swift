import Foundation
import Testing
import TextierCore

@Suite("File/line pairing")
struct FileLinePairingTests {
    let context = JSONValue.parse(Fixtures.monologContextJSON)!

    /// The paired line of the object `json`.
    func paired(_ json: String) -> Int? {
        guard case .object(let entries)? = JSONValue.parse(json) else {
            Issue.record("\(json) isn't an object")
            return nil
        }
        return pairedLine(in: entries, config: .default)
    }

    // MARK: Structural form

    @Test func theMonologBacktraceFramesPairWithTheirLines() throws {
        guard case .array(let frames)? = context["backtrace"] else {
            Issue.record("no backtrace")
            return
        }
        let lines = frames.map { frame -> Int? in
            guard case .object(let entries) = frame else { return nil }
            return pairedLine(in: entries, config: .default)
        }
        #expect(lines == [80, 118, 603, 552, 479])
    }

    @Test func callerFileAndCallerLineDontPair() throws {
        guard case .object(let entries) = context else { return }
        #expect(entries.contains { $0.key == "caller_file" })
        #expect(pairedLine(in: entries, config: .default) == nil)
    }

    @Test(arguments: [
        #"{"file":"/app/a.php","line":80}"#,
        #"{"line":80,"file":"/app/a.php"}"#,
        #"{"file":"/app/a.php","line":"80"}"#,
        #"{"file":"~/app/a.php","line":80}"#,
    ])
    func aNumberOrDigitStringLinePairs(json: String) {
        #expect(paired(json) == 80)
    }

    @Test(arguments: [
        #"{"file":"/app/a.php","line":0}"#,
        #"{"file":"/app/a.php","line":-80}"#,
        #"{"file":"/app/a.php","line":80.5}"#,
        #"{"file":"/app/a.php","line":8e1}"#,
        #"{"file":"/app/a.php","line":null}"#,
        #"{"file":"/app/a.php","line":true}"#,
        #"{"file":"/app/a.php","line":"80abc"}"#,
        #"{"file":"/app/a.php","line":" 80"}"#,
        #"{"file":"/app/a.php","line":""}"#,
        #"{"file":"/app/a.php","line":"0"}"#,
        #"{"file":"/app/a.php","line":99999999999999999999}"#,
        #"{"file":"/app/a.php"}"#,
    ])
    func aBadOrMissingLineDoesntPair(json: String) {
        #expect(paired(json) == nil)
    }

    @Test(arguments: [
        #"{"file":"a.php","line":80}"#,
        #"{"file":"see /app/a.php","line":80}"#,
        #"{"file":"https://a.test/a.php","line":80}"#,
        #"{"file":42,"line":80}"#,
        #"{"filename":"/app/a.php","lineno":80}"#,
        #"{"caller_file":"/app/a.php","caller_line":80}"#,
    ])
    func onlyAWholeFilePathUnderTheKeyFilePairs(json: String) {
        #expect(paired(json) == nil)
    }

    @Test func aPathsOwnLineWins() {
        #expect(paired(#"{"file":"/app/a.php:12","line":80}"#) == nil)
    }

    @Test func onlyTheFirstFileAndLineEntriesCount() {
        #expect(paired(#"{"file":"/app/a.php","line":80,"line":90}"#) == 80)
        #expect(paired(#"{"file":"/app/a.php","line":"x","line":90}"#) == nil)
        #expect(paired(#"{"file":"nope","file":"/app/a.php","line":80}"#) == nil)
    }

    // MARK: Textual form

    @Test func theMonologTargetsAreTheFrameFileContentsWithTheirLines() {
        let json = Fixtures.monologContextJSON
        let targets = fileLineTargets(in: json, config: .default)

        #expect(targets.map(\.line) == [80, 118, 603, 552, 479])
        let text = json as NSString
        #expect(targets.map { text.substring(with: $0.range) } == [
            "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Services/EmailTemplateService.php",
            "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php",
            "/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php",
            "/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php",
            "/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php",
        ])
    }

    @Test func targetRangesAreUTF16AndCoverTheContentAsWrittenEscapesIncluded() {
        // "é" is one UTF-16 unit and "🪵" two: the content starts at 27 (26 in
        // characters, 30 in UTF-8 bytes).
        let json = #"{"note":"é🪵","f":{"file":"\/app\/a.php","line":7}}"#
        let targets = fileLineTargets(in: json, config: .default)

        #expect(targets == [FileLineTarget(range: NSRange(location: 27, length: 12), line: 7)])
        #expect((json as NSString).substring(with: targets[0].range) == #"\/app\/a.php"#)
    }

    @Test func prettyPrintedTextHasTheSameTargets() {
        let pretty = JSONValue.parse(Fixtures.monologContextJSON)!.prettyPrinted
        let targets = fileLineTargets(in: pretty, config: .default)

        #expect(targets.map(\.line) == [80, 118, 603, 552, 479])
        #expect((pretty as NSString).substring(with: targets[2].range).hasSuffix("/Events/Dispatcher.php"))
    }

    @Test func escapedJSONInsideAStringIsntSearched() {
        let json = #"{"context":"{\"file\":\"/app/a.php\",\"line\":7}"}"#
        #expect(fileLineTargets(in: json, config: .default).isEmpty)
    }

    @Test func textThatIsntJSONHasNoTargets() {
        #expect(fileLineTargets(in: #"{"file":"/app/a.php","line":7"#, config: .default).isEmpty)
        #expect(fileLineTargets(in: "/app/a.php:7", config: .default).isEmpty)
    }

    @Test func aRootArrayOfFramesAndUnpairedOnesBetween() {
        let json = #"[{"file":"/a.php","line":1},{"file":"/b.php:3","line":2},{"line":4,"file":"/c.php"}]"#
        #expect(fileLineTargets(in: json, config: .default).map(\.line) == [1, 4])
    }

    @Test func aDisabledFilePathPatternPairsNothing() throws {
        var config = Config.default
        let index = try #require(config.patterns.firstIndex { $0.name == Preset.filePath.name })
        config.patterns[index].enabled = false
        guard case .object(let entries)? = JSONValue.parse(#"{"file":"/app/a.php","line":80}"#) else { return }
        #expect(pairedLine(in: entries, config: config) == nil)
    }
}
