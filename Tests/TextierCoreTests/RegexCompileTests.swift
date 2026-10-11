import Foundation
import Testing
import TextierCore

@Suite("Compiling a Pattern's regex")
struct RegexCompileTests {
    func compiled(_ source: String) throws -> CompiledRegex {
        try compileRegex(source).get()
    }

    func error(_ source: String) -> String? {
        guard case .failure(let error) = compileRegex(source) else { return nil }
        return error.message
    }

    /// The whole of each match of `source` in `text`.
    func matches(_ source: String, in text: String) throws -> [String] {
        let regex = try compiled(source).regex
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            (text as NSString).substring(with: $0.range)
        }
    }

    // MARK: Perl's spellings

    @Test(arguments: [#"(?P<id>\d+)"#, #"(?'id'\d+)"#, #"(?<id>\d+)"#])
    func namedGroupsCompileInEverySpelling(source: String) throws {
        #expect(try matches(source, in: "order 42") == ["42"])
        #expect(try compiled(source).fields.map(\.name) == ["id"])
    }

    @Test(arguments: [#"(?P<id>\d+)-(?P=id)"#, #"(?<id>\d+)-\k<id>"#, #"(?<id>\d+)-\k'id'"#, #"(?<id>\d+)-\k{id}"#, #"(?<id>\d+)-\g{id}"#])
    func namedBackreferencesMatchAsPerlReadsThem(source: String) throws {
        #expect(try matches(source, in: "12-12 12-13") == ["12-12"])
    }

    @Test func relativeAndBracedNumberedBackreferencesWork() throws {
        #expect(try matches(#"(a)(b)\g{-1}\g1"#, in: "abba abab") == ["abba"])
    }

    @Test(arguments: ["client_ip", "[client][ip]", "ip-v4", "π"])
    func anyWrittenNameCompilesAndIsKeptAsWritten(name: String) throws {
        let regex = try compiled(#"(?<\#(name)>\d+\.\d+\.\d+\.\d+)"#)
        #expect(regex.fields.map(\.name) == [name])
    }

    @Test func aNameWrittenTwiceGivesTwoFields() throws {
        #expect(try compiled(#"(?<tag>\w+) (?<tag>\w+)"#).fields.map(\.name) == ["tag", "tag"])
    }

    @Test func fieldsAreInGroupOrderAcrossNestingAndUnnamedGroups() throws {
        let regex = try compiled(#"(?<outer>(\w+) (?<inner>\d+)) (?P<last>x)"#)
        #expect(regex.fields.map(\.name) == ["outer", "inner", "last"])
    }

    @Test func perlLiteralBracesCompile() throws {
        #expect(try matches(#"\%{x}"#, in: "a %{x} b") == ["%{x}"])
        #expect(try matches(#"{a}"#, in: "{a}") == ["{a}"])
        #expect(try matches(#"a{2}b{1,}c{,2}"#, in: "aabbbcc") == ["aabbbcc"])
    }

    @Test func groupLikeTextInsideClassesAndQuotesIsLeftAlone() throws {
        #expect(try matches(#"[(?P<x>]+"#, in: "(?P<x>") == ["(?P<x>"])
        #expect(try matches(#"\Q(?R)\K\E"#, in: #"(?R)\K"#) == [#"(?R)\K"#])
        #expect(try compiled(#"[(?<a>)]"#).fields.isEmpty)
    }

    @Test func icuSyntaxItSharesWithPerlStillWorks() throws {
        #expect(try matches(#"(?i)(?<=\s)\p{Lu}++\b(?=!)"#, in: "say HELLO!") == ["HELLO"])
        #expect(try matches(#"(?x) a \  b  # a comment (?R)"#, in: "a b") == ["a b"])
        #expect(try matches(#"(?>a+)[[:digit:]]"#, in: "aa1") == ["aa1"])
    }

    // MARK: What ICU can't run

    @Test func backslashKIsRejectedNotReadAsALiteralK() {
        #expect(error(#"a\Kb"#) == #"\K isn't supported"#)
    }

    @Test(arguments: [
        (#"a(?R)?b"#, "(?R)"), (#"(a)(?1)"#, "(?1)"), (#"(a)(?-1)"#, "(?-1)"), (#"(a)(?+1)(b)"#, "(?+1)"),
        (#"(?<n>a)(?&n)"#, "(?&n)"), (#"(?P<n>a)(?P>n)"#, "(?P>n)"), (#"(?<n>a)\g<n>"#, #"\g<n>"#),
    ])
    func recursionAndSubroutinesAreRejectedByName(source: String, construct: String) throws {
        let message = try #require(error(source))
        #expect(message.contains(construct))
        #expect(message.contains("isn't supported"))
    }

    @Test(arguments: [
        (#"(a)?(?(1)b|c)"#, "conditional"), (#"(?|(a)|(b))"#, "branch reset"), (#"a(*SKIP)(*FAIL)|b"#, "(*SKIP)"),
        (#"(?^i:a)"#, "(?^"),
    ])
    func perlOnlyConstructsAreRejectedByName(source: String, construct: String) throws {
        let message = try #require(error(source))
        #expect(message.contains(construct))
    }

    @Test func icuErrorsSayWhyAndWhere() throws {
        #expect(error(#"(?<=a+)b"#) == "lookbehind must have a bounded length (at character 7)")
        #expect(error(#"ab(c"#) == "unbalanced parenthesis (at character 4)")
        let unclosed = try #require(error(#"[a-"#))
        #expect(unclosed.contains("at character"))
    }

    @Test func anUnescapedBracketInsideAClassIsANestedClassAsInICU() throws {
        // Perl would read the inner `[` as a literal; ICU opens a nested class, so
        // the outer one is never closed.
        #expect(error(#"\[([^[\]]*)\]"#)
            == #"unescaped [ inside a character class starts a nested class; write \[ (at character 6)"#)
        #expect(try matches(#"\[([^\[\]]*)\]"#, in: "a [b] c") == ["[b]"])
        #expect(try matches(#"[a[bc]]+"#, in: "xcab") == ["cab"])
        // A nested class that closes, then an unclosed one without any, keeps ICU's
        // reason; a POSIX class isn't one either.
        #expect(error(#"[a[bc]]x[yz"#)?.hasPrefix("unclosed [ (at") == true)
        #expect(error(#"[[:alpha:]"#)?.hasPrefix("unclosed [ (at") == true)
    }

    @Test func anUnfinishedGroupNameIsAnError() {
        #expect(error(#"(?<x"#) == "unclosed group name (?<x")
        #expect(error(#"(?<>a)"#) == "a named group needs a name")
    }

    @Test func aBackreferenceToAnUnknownNameIsAnError() {
        #expect(error(#"(?<a>x)\k<b>"#) == #"no group named "b""#)
    }

    @Test func icuPositionsPointIntoTheRegexAsWritten() throws {
        // The renamed group makes the ICU source longer than what was written.
        #expect(error(#"(?<client_ip>\d+)(?<=a*)"#) == "lookbehind must have a bounded length (at character 24)")
    }

    @Test func icuPositionsCountEveryLineAndUTF16Unit() {
        // ICU counts code points within a line; positions here are UTF-16 units in the whole regex.
        #expect(error("(?x)a\nb\nc)") == "unbalanced parenthesis (at character 10)")
        #expect(error("(?x)a\r\nb)") == "unbalanced parenthesis (at character 9)")
        #expect(error("😀)") == "unbalanced parenthesis (at character 3)")
    }

    // MARK: Numbered backreferences

    @Test func aDigitAfterANumberedBackreferenceStaysALiteral() throws {
        let source = #"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)\g{1}0"#
        #expect(try matches(source, in: "abcdefghija0") == ["abcdefghija0"])
        #expect(try matches(source, in: "abcdefghijj").isEmpty)
        // A quantifier after one still repeats the whole reference.
        #expect(try matches(#"(ab)\g1{2}"#, in: "ababab ababb") == ["ababab"])
    }

    // MARK: U+0001

    @Test func aRegexWithUPlus0001IsAnErrorNotAGrokField() {
        let message = "control character U+0001 isn't allowed in a regex"
        #expect(error("(?<\u{1}5>x)") == message)
        #expect(error("(?<\u{1}0>x)") == message)
        #expect(error("\\\u{1}") == message)
        guard case .failure(let error) = compileRegex("%{ODD}", grok: [GrokDefinition(name: "ODD", regex: "(?<\u{1}0>x)")])
        else {
            Issue.record("a definition with U+0001 compiled")
            return
        }
        #expect(error.message == message)
    }

    // MARK: Compiled once

    @Test func compilingTheSameSourceTwiceReusesTheRegex() throws {
        #expect(try compiled(#"\bonce\b"#).regex === compiled(#"\bonce\b"#).regex)
    }

    @Test func optionsAreCompiledAndCachedApart() throws {
        let ignoringCase = try compileRegex("warn", options: .caseInsensitive).get().regex
        let exact = try compiled("warn").regex
        #expect(ignoringCase !== exact)
        #expect(ignoringCase.firstMatch(in: "WARN", range: NSRange(location: 0, length: 4)) != nil)
        #expect(exact.firstMatch(in: "WARN", range: NSRange(location: 0, length: 4)) == nil)
    }
}
