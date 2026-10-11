/// Turns "open this path at this line" into the argument vector of an editor command.
public enum EditorCommand {
    /// Editors that take a line number, by executable name, and how: `cursor` and
    /// `code` want `-g path:line`, `zed` and `subl` want `path:line`.
    private static let lineFlags: [String: [String]] = [
        "cursor": ["-g"],
        "code": ["-g"],
        "zed": [],
        "subl": [],
    ]

    /// Editors that need a terminal. textier runs the editor without one, so a
    /// `$EDITOR` naming one of these is passed over for the default.
    private static let terminalEditors: Set<String> = [
        "vi", "vim", "nvim", "view", "ex", "ed", "nano", "pico", "emacs", "hx", "helix",
        "micro", "kak", "joe", "mg", "jed", "ne",
    ]

    /// What runs when neither a template nor a usable `$EDITOR` is set: `cursor -g {path}:{line}`.
    private static let defaultEditor = "cursor"

    /// The arguments (executable first) that open `path`, at `line` when given.
    ///
    /// Precedence:
    /// 1. `template`, the config's `editorCommand`. It is split shell-style (spaces
    ///    separate arguments; `'…'`, `"…"` and `\` quote), then `{path}` and `{line}`
    ///    are substituted inside each argument, so a path with spaces stays one
    ///    argument. With no line, `:{line}` is dropped, and an argument that is just
    ///    `{line}` is dropped along with a flag (`-x`, `--x`) right before it. A
    ///    template without `{path}` gets the path appended.
    /// 2. `editor`, the login shell's `$EDITOR`, which may carry flags (`code --wait`).
    ///    Known GUI editors, recognised by the executable's basename, get their line
    ///    argument; any other editor gets just the path. Terminal editors (`vi`,
    ///    `nvim`, `nano`, …) can't run without a terminal, so they fall through to 3.
    /// 3. `cursor -g {path}:{line}`.
    ///
    /// A blank template or editor counts as unset.
    public static func arguments(template: String?, editor: String?, path: String, line: Int?) -> [String] {
        if let template = nonBlank(template) {
            return substitute(split(template), path: path, line: line)
        }
        var editorArguments = nonBlank(editor).map(split) ?? []
        if editorArguments.first.map(basename).map(terminalEditors.contains) ?? true {
            editorArguments = [defaultEditor]
        }
        guard let flags = lineFlags[basename(editorArguments[0])] else { return editorArguments + [path] }
        guard let line else { return editorArguments + [path] }
        return editorArguments + flags + ["\(path):\(line)"]
    }

    private static func basename(_ executable: String) -> String {
        executable.split(separator: "/").last.map(String.init) ?? executable
    }

    private static func nonBlank(_ string: String?) -> String? {
        guard let string, string.contains(where: { !$0.isWhitespace }) else { return nil }
        return string
    }

    private static func substitute(_ tokens: [String], path: String, line: Int?) -> [String] {
        var arguments: [String] = []
        var sawPath = false
        for token in tokens {
            if token == "{line}", line == nil {
                if arguments.count > 1, arguments.last?.hasPrefix("-") == true { arguments.removeLast() }
                continue
            }
            sawPath = sawPath || token.contains("{path}")
            arguments.append(fill(token, path: path, line: line))
        }
        return sawPath ? arguments : arguments + [path]
    }

    /// Replaces the placeholders in one pass, so a path that itself contains
    /// `{line}` is left alone.
    private static func fill(_ token: String, path: String, line: Int?) -> String {
        var output = ""
        var rest = Substring(token)
        while !rest.isEmpty {
            if rest.hasPrefix("{path}") {
                output += path
                rest = rest.dropFirst("{path}".count)
            } else if rest.hasPrefix(":{line}"), line == nil {
                rest = rest.dropFirst(":{line}".count)
            } else if rest.hasPrefix("{line}") {
                output += line.map(String.init) ?? ""
                rest = rest.dropFirst("{line}".count)
            } else {
                output.append(rest.removeFirst())
            }
        }
        return output
    }

    /// Splits a command line the way a shell would, minus expansions: whitespace
    /// separates arguments, single quotes are literal, double quotes allow `\"` and
    /// `\\`, and a backslash outside quotes escapes the next character.
    static func split(_ command: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var inArgument = false
        var quote: Character?
        var characters = command.makeIterator()
        while let character = characters.next() {
            switch (quote, character) {
            case ("'", "'"), ("\"", "\""):
                quote = nil
            case ("\"", "\\"):
                guard let next = characters.next() else { current.append(character); break }
                if next != "\"", next != "\\" { current.append(character) }
                current.append(next)
            case (nil, "'"), (nil, "\""):
                quote = character
                inArgument = true
            case (nil, "\\"):
                if let next = characters.next() { current.append(next) }
                inArgument = true
            case (nil, _) where character.isWhitespace:
                if inArgument { arguments.append(current) }
                current = ""
                inArgument = false
            default:
                current.append(character)
                inArgument = true
            }
        }
        if inArgument { arguments.append(current) }
        return arguments
    }
}

/// Where a file path Match points: the file, and the line and column from an
/// optional `:line[:col]` suffix.
public struct FileLocation: Sendable, Equatable {
    public var path: String
    public var line: Int?
    public var column: Int?

    public init(path: String, line: Int? = nil, column: Int? = nil) {
        self.path = path
        self.line = line
        self.column = column
    }

    /// Parses a file path Match's text. A leading `~/` expands against `homeDirectory`.
    public init(matchText: String, homeDirectory: String) {
        var parts = matchText.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var numbers: [Int] = []
        // Up to two trailing all-digit parts are line and column; the rest is the path.
        while numbers.count < 2, parts.count > 1, let last = parts.last,
              !last.isEmpty, last.allSatisfy(\.isASCII), let number = Int(last), number > 0 {
            numbers.insert(number, at: 0)
            parts.removeLast()
        }
        var path = parts.joined(separator: ":")
        if path.hasPrefix("~/") {
            let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
            path = home + path.dropFirst()
        }
        self.init(path: path, line: numbers.first, column: numbers.count > 1 ? numbers[1] : nil)
    }
}
