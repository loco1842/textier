import Foundation

/// Parses a Match for display, by what its Pattern is for: the `json` Built-in as
/// JSON; a Pattern offering `open-url` as a URL; one offering `open-file` as a file
/// path; the Pattern named `datetime` as a datetime. Anything else (log level, User
/// Patterns), and any text its parser rejects, is shown as text.
struct DetailParser {
    var config: Config
    var now: Date
    var timeZone: TimeZone
    var homeDirectory: String

    /// `pairedLine` is the line a file path takes from its JSON object's `line` key;
    /// the path's own `:line` wins. `fileExists` is asked about file paths, after
    /// `~/` expansion.
    func detail(of match: Match, pairedLine: Int? = nil, fileExists: @Sendable (String) -> Bool) -> Detail {
        let parsed: Detail? = switch config.pattern(of: match)?.kind {
        case .builtin(.json): JSONValue.container(from: match.text).map(Detail.json)
        case .builtin(.escapedJSON): nil
        case .regex, nil:
            if match.actions.contains(.openURL) {
                urlDetail(match.text).map(Detail.url)
            } else if match.actions.contains(.openFile) {
                .filePath(filePathDetail(match.text, pairedLine: pairedLine, fileExists: fileExists))
            } else if match.patternName == Preset.datetime.name {
                datetimeDetail(match.text, now: now, timeZone: timeZone).map(Detail.datetime)
            } else {
                nil
            }
        }
        return parsed ?? .text(match.text)
    }

    private func filePathDetail(_ text: String, pairedLine: Int?, fileExists: (String) -> Bool) -> FilePathDetail {
        let location = FileLocation(matchText: text, homeDirectory: homeDirectory)
        let paired = location.line == nil ? pairedLine : nil
        return FilePathDetail(
            path: location.path, line: location.line ?? paired, column: location.column,
            exists: fileExists(location.path), lineSource: paired == nil ? nil : .lineKey
        )
    }
}

/// A URL's parts, or nil when `text` has no scheme or host. Query parameters keep
/// their order and repeats; names and values are percent-decoded, and `+` is left
/// as is.
///
/// Foundation reads a URL with characters it would have to encode (`日本`, `|`) by
/// encoding them, the `%` of its escapes too, so such a URL's path, query and
/// fragment are read from the text as written and decoded once.
func urlDetail(_ text: String) -> URLDetail? {
    let strict = URLComponents(string: text, encodingInvalidCharacters: false)
    guard let components = strict ?? URLComponents(string: text), let scheme = components.scheme,
          let host = components.host, !host.isEmpty
    else { return nil }
    func decoded(_ part: Substring?) -> String {
        guard let part else { return "" }
        return part.removingPercentEncoding ?? String(part)
    }
    var path = components.path
    var encodedQuery = components.percentEncodedQuery?[...]
    var fragment = components.fragment
    if strict == nil {
        let written = writtenParts(of: text)
        path = decoded(written.path)
        encodedQuery = written.query
        fragment = written.fragment.map { decoded($0) }
    }
    let query = (encodedQuery ?? "").split(separator: "&").map { pair in
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        return QueryParameter(name: decoded(parts.first), value: decoded(parts.count > 1 ? parts[1] : nil))
    }
    return URLDetail(
        scheme: scheme, host: host, port: components.port, path: path, query: query, fragment: fragment
    )
}

/// A URL's path, query and fragment as written: the path from the first `/` after
/// the authority, the query after the first `?`, the fragment after the first `#`.
private func writtenParts(of text: String) -> (path: Substring, query: Substring?, fragment: Substring?) {
    let hash = text.firstIndex(of: "#")
    let fragment = hash.map { text[text.index(after: $0)...] }
    let beforeFragment = text[..<(hash ?? text.endIndex)]
    let mark = beforeFragment.firstIndex(of: "?")
    let query = mark.map { beforeFragment[beforeFragment.index(after: $0)...] }
    let beforeQuery = beforeFragment[..<(mark ?? beforeFragment.endIndex)]
    let authority = beforeQuery.range(of: "://")?.upperBound ?? beforeQuery.startIndex
    let path = beforeQuery[authority...].firstIndex(of: "/").map { beforeQuery[$0...] } ?? ""
    return (path, query, fragment)
}
