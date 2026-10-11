import Foundation
import Testing
import TextierCore

@Suite("Grok Definitions")
struct GrokTests {
    /// The names StreamSets documents, in its order.
    static let streamSetsNames = """
    USER USERNAME BASE10NUM BASE16FLOAT INT NONNEGINT NUMBER BASE16NUM POSINT WORD NOTSPACE SPACE DATA GREEDYDATA
    QUOTEDSTRING UUID MONTH MONTHNUM MONTHNUM2 MONTHDAY DAY YEAR HOUR MINUTE SECOND TIME DATE_US DATE_EU
    ISO8601_TIMEZONE ISO8601_SECOND TIMESTAMP_ISO8601 DATE DATESTAMP TZ DATESTAMP_RFC822 DATESTAMP_RFC2822
    DATESTAMP_OTHER DATESTAMP_EVENTLOG JAVACLASS JAVAFILE JAVAMETHOD JAVASTACKTRACEPART SYSLOGTIMESTAMP PROG
    SYSLOGPROG SYSLOGHOST SYSLOGFACILITY SYSLOGBASE HTTPDATE QS COMMONAPACHELOG COMBINEDAPACHELOG LOGLEVEL MAC
    CISCOMAC COMMONMAC WINDOWSMAC HOST HOSTNAME HOSTPORT IPORHOST IP IPV6 IPV4 PATH UNIXPATH TTY WINPATH URIPROTO
    URIHOST URIPATH URIPARAM URIPATHPARAM URI
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    func compiled(_ source: String, grok: [GrokDefinition] = []) throws -> CompiledRegex {
        try compileRegex(source, grok: grok).get()
    }

    func error(_ source: String, grok: [GrokDefinition] = []) -> String? {
        guard case .failure(let error) = compileRegex(source, grok: grok) else { return nil }
        return error.message
    }

    func matches(_ source: String, in text: String, grok: [GrokDefinition] = []) throws -> [String] {
        let regex = try compiled(source, grok: grok).regex
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            (text as NSString).substring(with: $0.range)
        }
    }

    // MARK: The bundled library

    @Test func everyStreamSetsNameIsBundledInItsOrder() {
        #expect(Self.streamSetsNames.count == 74)
        let bundled = GrokDefinition.bundled.map(\.name)
        #expect(Array(bundled.prefix(Self.streamSetsNames.count)) == Self.streamSetsNames)
        #expect(Set(bundled).count == bundled.count)
    }

    @Test(arguments: GrokDefinition.bundled.map(\.name))
    func everyBundledDefinitionCompilesOnItsOwn(name: String) throws {
        _ = try compiled("%{\(name)}")
    }

    @Test func bundledDefinitionsMatchWhatTheirNamesSay() throws {
        #expect(try matches("%{IPV4}", in: "from 192.168.1.20 to 300.1.1.1") == ["192.168.1.20"])
        #expect(try matches("%{TIMESTAMP_ISO8601}", in: "at 2026-10-09T10:15:32+07:00 done") == ["2026-10-09T10:15:32+07:00"])
        #expect(try matches("%{LOGLEVEL}", in: "2026 WARN boot") == ["WARN"])
        #expect(try matches("%{JAVACLASS}", in: "com.example.billing.InvoiceService") == ["com.example.billing.InvoiceService"])
        #expect(try matches("%{UNIXPATH}", in: "see /usr/local/$app/x~1.log") == ["/usr/local/$app/x~1.log"])
        #expect(try matches("%{HTTPDATE}", in: "[09/Oct/2026:10:15:32 +0700]") == ["09/Oct/2026:10:15:32 +0700"])
    }

    @Test func aURIPatternRunsQuicklyOverWordsThatArentURIs() throws {
        // URIPROTO's repeated group used to backtrack for seconds over a long word without `://`.
        let config = Config(patterns: [Pattern(name: "uri", regex: "%{URI}", actions: [.copy])])
        let input = "id 3f2b8c1e-9a4d-4e6f-8b7a-2c1d0e9f8a7b " + String(repeating: "a", count: 40) + " "
        let start = ContinuousClock.now
        let found = detect(input + "then https://example.com/x", config: config)
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(found.map(\.text) == ["https://example.com/x"])
        #expect(try matches("%{URIPROTO}://", in: "git+ssh://host") == ["git+ssh://"])
    }

    // MARK: Expansion

    @Test func aNamedReferenceIsAFieldAndABareOneIsNot() throws {
        #expect(try compiled("%{IPV4:client} %{WORD}").fields.map(\.name) == ["client"])
    }

    @Test func definitionsNestAndTheirOwnFieldsComeAlongInOrder() throws {
        let fields = try compiled("%{SYSLOGBASE}").fields.map(\.name)
        #expect(fields == ["timestamp", "facility", "priority", "logsource", "program", "pid"])
    }

    @Test func aTypeIsReadAndShownInTheLabel() throws {
        let regex = try compiled("took %{NUMBER:ms:int}ms, %{NUMBER:ratio:float}")
        #expect(regex.fields.map(\.name) == ["ms", "ratio"])
        #expect(regex.fields.map(\.type) == ["int", "float"])
        let match = try #require(detect("took 12ms, 0.5", config: Config(patterns: [
            Pattern(name: "timing", regex: "took %{NUMBER:ms:int}ms", actions: [.copy]),
        ])).first)
        #expect(match.fields.map(\.label) == ["ms (int)"])
    }

    @Test func aTypeOtherThanIntOrFloatIsAnError() {
        #expect(error("%{NUMBER:ms:long}") == #"grok type "long" in %{NUMBER:ms:long} isn't int or float"#)
    }

    @Test func anEscapedPercentBraceStaysLiteral() throws {
        #expect(try matches(#"\%{x}"#, in: "a %{x} b") == ["%{x}"])
    }

    @Test func anUnknownNameIsAnErrorNamingIt() {
        #expect(error("%{NOPE}") == "unknown grok definition NOPE")
    }

    @Test func aLoopIsAnErrorNamingIt() {
        let grok = [GrokDefinition(name: "A", regex: "a%{B}"), GrokDefinition(name: "B", regex: "b%{A}")]
        #expect(error("%{A}", grok: grok) == "grok definitions loop: A → B → A")
        #expect(error("%{SELF}", grok: [GrokDefinition(name: "SELF", regex: "x%{SELF}")]) == "grok definitions loop: SELF → SELF")
    }

    @Test func aDefinitionPastedFromLogstashKeepsItsNestedPOSIXClass() throws {
        // Logstash's own UNIXPATH, `$` escaped: the nested class is why `[` inside a
        // class stays ICU's and Oniguruma's (ADR-0004).
        let grok = [GrokDefinition(name: "MYPATH", regex: #"(/[[[:alnum:]]_%!\$@:.,+~-]*)+"#)]
        #expect(try matches("%{MYPATH}", in: "see /usr/local/x_1.log", grok: grok) == ["/usr/local/x_1.log"])
    }

    @Test func aNestedClassLeftOpenInADefinitionNamesTheReference() {
        let grok = [GrokDefinition(name: "BRACKETED", regex: #"\[[^[\]]*\]"#)]
        #expect(error("x %{BRACKETED}", grok: grok)
            == #"unescaped [ inside a character class starts a nested class; write \[ in %{BRACKETED} (at character 3)"#)
    }

    @Test func aClassLeftOpenBeforeAReferenceIsntBlamedOnTheDefinitionsOwnClass() throws {
        // UNIXPATH's `[` is a correct class of its own, inside the one `[a-z` leaves open.
        // The class left open is named where it opens.
        #expect(error("[a-z %{UNIXPATH}") == "unclosed [ (at character 1)")
        #expect(error("user=[a-z+ path=%{UNIXPATH}") == "unclosed [ (at character 6)")
        // A `[` the regex itself writes inside the open class is still the cause,
        // before the definition's class or after it.
        #expect(error("[a-z [b %{UNIXPATH}")
            == #"unescaped [ inside a character class starts a nested class; write \[ (at character 6)"#)
        #expect(error("[a-z %{UNIXPATH} [b")
            == #"unescaped [ inside a character class starts a nested class; write \[ (at character 18)"#)
    }

    @Test func anICUErrorInsideADefinitionNamesTheReference() {
        let grok = [GrokDefinition(name: "BAD", regex: "(?<=a+)b")]
        #expect(error("x %{BAD}", grok: grok) == "lookbehind must have a bounded length in %{BAD} (at character 3)")
    }

    // MARK: The user's own

    @Test func aUserDefinitionCanBeUsedByName() throws {
        let grok = [GrokDefinition(name: "MYTICKET", regex: #"[A-Z]+-\d+"#)]
        #expect(try matches("%{MYTICKET}", in: "see ABC-12", grok: grok) == ["ABC-12"])
    }

    @Test func aUserDefinitionReplacesABundledOneEverywhere() throws {
        let grok = [GrokDefinition(name: "USERNAME", regex: "[a-z]+")]
        #expect(try matches("%{USERNAME}", in: "Ann.B", grok: grok) == ["nn"])
        // USER is %{USERNAME}, so it follows.
        #expect(try matches("%{USER}", in: "Ann.B", grok: grok) == ["nn"])
        #expect(try matches("%{USER}", in: "Ann.B") == ["Ann.B"])
        let level = [GrokDefinition(name: "LOGLEVEL", regex: "(?:WARN|ERR)")]
        #expect(try matches("%{LOGLEVEL}", in: "INFO WARN", grok: level) == ["WARN"])
    }

    // MARK: Real log lines

    @Test func theNginxAccessPatternShowsFourFields() throws {
        let access = Pattern(
            name: "access", regex: #"%{IPV4:client} - - \[%{HTTPDATE:time}\] "%{WORD:method} %{URIPATHPARAM:path}"#,
            actions: [.copy]
        )
        let entry = try #require(
            inspectFixed(Fixtures.nginxAccessLine, config: Config(patterns: Config.default.patterns + [access]))
                .entries(.pattern("access")).first
        )
        #expect(entry.fields.map(\.field.label) == ["client", "time", "method", "path"])
        #expect(entry.fields.map(\.field.value) == [
            "203.0.113.7", "09/Oct/2026:10:15:32 +0700", "GET", "/api/v1/signin?next=%2Fhome",
        ])
    }

    @Test func aJavaLogLineAndItsStackFrame() throws {
        let line = Pattern(
            name: "java log", regex: #"%{TIMESTAMP_ISO8601:time} %{LOGLEVEL:level} \[%{DATA:thread}\] %{JAVACLASS:class}"#,
            actions: [.copy]
        )
        let frame = Pattern(name: "java frame", regex: "%{JAVASTACKTRACEPART}", actions: [.copy])
        let inspection = inspectFixed(Fixtures.javaLogLines, config: Config(patterns: [line, frame]))

        let log = try #require(inspection.entries(.pattern("java log")).first)
        #expect(log.fields.map(\.field.value) == [
            "2026-10-09 10:15:32,118", "ERROR", "main", "com.example.billing.InvoiceService",
        ])
        let stack = try #require(inspection.entries(.pattern("java frame")).first)
        #expect(stack.fields.map(\.field.name) == ["class", "method", "file", "line"])
        #expect(stack.fields.map(\.field.value) == ["com.example.billing.InvoiceService", "charge", "InvoiceService.java", "87"])
    }

    @Test func detectUsesTheConfigsGrokDefinitions() throws {
        var config = Config(patterns: [Pattern(name: "ticket", regex: "%{MYTICKET}", actions: [.copy])])
        config.grok = [GrokDefinition(name: "MYTICKET", regex: #"[A-Z]+-\d+"#)]
        #expect(detect("fix ABC-12 now", config: config).map(\.text) == ["ABC-12"])
    }
}
