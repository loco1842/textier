import Foundation
import Testing
import TextierCore

@Suite("Fields: named captures in a Match's parsed view")
struct FieldTests {
    func config(_ patterns: Pattern...) -> Config {
        Config(patterns: Config.default.patterns + patterns)
    }

    func entry(_ name: String, _ index: Int = 0, in input: String, config: Config) throws -> InspectorEntry {
        let entries = inspectFixed(input, config: config).entries(.pattern(name))
        return try #require(entries.indices.contains(index) ? entries[index] : nil)
    }

    let access = Pattern(name: "access", regex: #"(?<client>\d+\.\d+\.\d+\.\d+) - - \[[^\]]+\] "\w+ (?<path>/[^\s?]+)"#, actions: [.copy])

    @Test func namedCapturesAreRowsInRegexOrder() throws {
        let entry = try entry("access", in: Fixtures.nginxAccessLine, config: config(access))

        #expect(entry.fields.map(\.field.name) == ["client", "path"])
        #expect(entry.fields.map(\.field.value) == ["203.0.113.7", "/api/v1/signin"])
        let line = Fixtures.nginxAccessLine as NSString
        #expect(entry.fields.map { line.substring(with: $0.field.range) } == ["203.0.113.7", "/api/v1/signin"])
        #expect(entry.fields.map(\.field.label) == ["client", "path"])
    }

    @Test func aMatchKeepsItsFieldsInDetect() throws {
        let match = try #require(detect("x 10.0.0.1 - - [d] \"GET /a HTTP/1.1\"", config: Config(patterns: [access])).first)
        #expect(match.fields.map(\.value) == ["10.0.0.1", "/a"])
    }

    @Test func unnamedGroupsGiveNoField() throws {
        let pattern = Pattern(name: "pair", regex: #"(\w+)=(?<value>\d+)"#, actions: [.copy])
        let entry = try entry("pair", in: "retries=3", config: config(pattern))

        #expect(entry.fields.map(\.field.name) == ["value"])
    }

    @Test func anOptionalGroupThatDidntTakePartGivesNoRow() throws {
        let pattern = Pattern(name: "user", regex: #"@(?<name>\w+)(?:#(?<tag>\d+))?"#, actions: [.copy])
        let config = config(pattern)

        #expect(try entry("user", in: "ping @ana#42", config: config).fields.map(\.field.name) == ["name", "tag"])
        #expect(try entry("user", in: "ping @ana", config: config).fields.map(\.field.name) == ["name"])
    }

    @Test func aNameWrittenTwiceGivesARowEachInOrder() throws {
        let pattern = Pattern(name: "tags", regex: #"tags: (?<tag>\w+) (?<tag>\w+)"#, actions: [.copy])
        let entry = try entry("tags", in: "tags: red blue", config: config(pattern))

        #expect(entry.fields.map(\.field.name) == ["tag", "tag"])
        #expect(entry.fields.map(\.field.value) == ["red", "blue"])
    }

    @Test func aFieldIsLabelledWithItsNameAsWritten() throws {
        let pattern = Pattern(name: "client", regex: #"from (?<[client][ip]>[\d.]+)"#, actions: [.copy])
        let entry = try entry("client", in: "from 10.1.2.3", config: config(pattern))

        #expect(entry.fields.map(\.field.label) == ["[client][ip]"])
    }

    @Test func aFieldThatIsAURLOrFilePathOffersThatMatchsActions() throws {
        let pattern = Pattern(
            name: "redirect", regex: #"(?<path>/\S+) -> (?<target>https?://\S+) \((?<code>\d+)\)"#, actions: [.copy]
        )
        let entry = try entry("redirect", in: "/var/log/app.log -> https://a.test/x (301)", config: config(pattern))

        #expect(entry.fields.map(\.link?.actions) == [[.openFile, .copy], [.openURL, .copy], nil])
        #expect(entry.fields.first?.link?.text == "/var/log/app.log")
    }

    @Test func aURLPatternWithFieldsHasBothTheFieldsAndTheURLsParts() throws {
        let pattern = Pattern(
            name: "api", regex: #"https://api\.test/(?<version>v\d+)/(?<resource>\w+)"#, actions: [.openURL, .copy]
        )
        let entry = try entry("api", in: "GET https://api.test/v2/users", config: Config(patterns: [pattern]))

        #expect(entry.fields.map(\.field.value) == ["v2", "users"])
        guard case .url(let url) = entry.detail else {
            Issue.record("expected a URL detail, got \(entry.detail)")
            return
        }
        #expect(url.path == "/v2/users")
    }

    @Test func matchesWithoutNamedGroupsHaveNoFields() {
        let monolog = inspectFixed(Fixtures.monologLine)
        #expect(monolog.tabs.allSatisfy { $0.entries.allSatisfy { $0.fields.isEmpty } })
    }
}
