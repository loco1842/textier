import Foundation

/// One step from a JSON value to a value inside it.
public enum JSONPathComponent: Sendable, Equatable {
    case key(String)
    case index(Int)
}

/// The key path of the value reached by `components` from the root, such as
/// `backtrace[0].file`: object keys in dot notation, array indices in brackets, and
/// keys that aren't plain identifiers bracket-quoted as JSON strings
/// (`headers["content-type"]`). The root itself is the empty path.
public func keyPath(_ components: [JSONPathComponent]) -> String {
    var path = ""
    for component in components {
        switch component {
        case .index(let index):
            path += "[\(index)]"
        case .key(let key) where isIdentifier(key):
            path += path.isEmpty ? key : "." + key
        case .key(let key):
            path += "[" + JSONValue.string(key).prettyPrinted + "]"
        }
    }
    return path
}

/// `[A-Za-z_$][A-Za-z0-9_$]*`, ASCII only.
private func isIdentifier(_ key: String) -> Bool {
    guard let first = key.unicodeScalars.first else { return false }
    func isStart(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || scalar == "_" || scalar == "$"
    }
    return isStart(first) && key.unicodeScalars.dropFirst().allSatisfy { isStart($0) || ("0"..."9").contains($0) }
}

extension JSONValue {
    /// Containers expanded when the JSON Viewer opens are those at depth 2 or less
    /// (the root is depth 0, its entries depth 1), so rows down to depth 3 show:
    /// a Monolog `backtrace` and each of its frames are open.
    public static let initialExpansionDepth = 2
    /// Arrays with more items than this start collapsed at any depth.
    public static let collapsedArrayThreshold = 20

    /// Whether this value starts expanded in the JSON Viewer when it sits at `depth`.
    public func isExpandedOnOpen(atDepth depth: Int) -> Bool {
        switch self {
        case .array(let elements):
            elements.count <= Self.collapsedArrayThreshold && depth <= Self.initialExpansionDepth
        case .object:
            depth <= Self.initialExpansionDepth
        default:
            false
        }
    }

    /// What "copy value" puts on the pasteboard: a scalar's raw value (a string
    /// unquoted and unescaped, a number as its source text) or a container as pretty JSON.
    public var copyText: String {
        switch self {
        case .string(let string): string
        case .number(let source): source
        case .object, .array, .bool, .null: prettyPrinted
        }
    }

    /// The JSON a string value holds, when its (already unescaped) content parses as
    /// a non-empty object or array: the `escaped-json` Built-in Pattern's rule. Nil
    /// for strings that merely contain braces, hold a scalar or an empty container,
    /// and for anything that isn't a string.
    public var escapedJSON: JSONValue? {
        guard case .string(let string) = self, let parsed = JSONValue.parse(string),
              parsed.isNonEmptyContainer
        else { return nil }
        return parsed
    }

    /// The value of the first entry named `key`, when this is an object.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let entries) = self else { return nil }
        return entries.first { $0.key == key }?.value
    }
}

/// The Match a JSON string value is in its entirety, so the JSON Viewer can offer
/// its Actions (`open-url` on a URL, `open-file` on a path). Only regex Patterns
/// whose Actions include `open-url` or `open-file` apply: a datetime string isn't
/// a link, and JSON inside a string value is the `escaped-json` Pattern's concern.
public func stringValueMatch(_ string: String, config: Config) -> Match? {
    stringValueMatch(string, config: config, budget: MatchingBudget())
}

// MARK: Row text

extension JSONValue {
    /// What a collapsed object or array shows in the JSON Viewer: a backtrace frame
    /// (an object with `file` and `line`) as `{ File.php:80 › function() }`, another
    /// object as its first four keys, an array as its size. Nil for anything else.
    public var collapsedPreview: String? {
        switch self {
        case .object(let entries):
            if case .string(let file)? = self["file"], let line = self["line"] {
                let name = file.split(separator: "/").last.map(String.init) ?? file
                let lineText = switch line {
                case .number(let source): source
                case .string(let string): string
                default: ""
                }
                var preview = name + (lineText.isEmpty ? "" : ":" + lineText)
                if case .string(let function)? = self["function"], !function.isEmpty { preview += " › \(function)()" }
                return "{ \(preview) }"
            }
            guard !entries.isEmpty else { return "{ }" }
            let keys = entries.prefix(4).map(\.key).joined(separator: ", ")
            return "{ \(keys)\(entries.count > 4 ? ", …" : "") }"
        case .array(let elements):
            return "[ \(counted(elements.count, "item")) ]"
        default:
            return nil
        }
    }

    /// What an expanded object or array shows: its size ("8 keys", "5 items"); empty
    /// for anything else.
    public var openSummary: String {
        switch self {
        case .object(let entries): counted(entries.count, "key")
        case .array(let elements): counted(elements.count, "item")
        default: ""
        }
    }
}

private func counted(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}

/// Whether a JSON Viewer search for `query` finds this node: its key (nil for the
/// root) contains it, or, for a leaf, its value's text does, ignoring case. A
/// container's entries don't make it match; they match on their own. A blank
/// query finds nothing.
public func jsonSearchMatches(key: String?, value: JSONValue, query: String) -> Bool {
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return false }
    if let key, key.localizedCaseInsensitiveContains(query) { return true }
    let text: String? = switch value {
    case .string(let string): string
    case .number(let source): source
    case .bool(let bool): bool ? "true" : "false"
    case .null: "null"
    case .object, .array: nil
    }
    return text?.localizedCaseInsensitiveContains(query) ?? false
}
