import Foundation

/// A textier version, as releases are tagged: `1.2.3`, `v1.2.3`, `0.0.0-dev.7`.
/// Compared as semantic versions: the numbers by value (a missing one is 0), and
/// a pre-release (`-dev.7`) before the release it leads to.
public struct AppVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let numbers: [Int]
    /// The pre-release's dot-separated parts; empty for a release.
    public let prerelease: [String]

    public init?(_ text: String) {
        var text = Substring(text.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        // Build metadata (`+…`) doesn't order versions.
        if let plus = text.firstIndex(of: "+") { text = text[..<plus] }
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        self.numbers = numbers.compactMap(\.self) + Array(repeating: 0, count: 3 - numbers.count)
        if parts.count == 2 {
            let prerelease = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard prerelease.allSatisfy({ !$0.isEmpty }) else { return nil }
            self.prerelease = prerelease
        } else {
            prerelease = []
        }
    }

    public var description: String {
        numbers.map(String.init).joined(separator: ".") + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        if a.numbers != b.numbers { return a.numbers.lexicographicallyPrecedes(b.numbers) }
        // A release comes after its pre-releases.
        switch (a.prerelease.isEmpty, b.prerelease.isEmpty) {
        case (true, _): return false
        case (false, true): return true
        case (false, false): break
        }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }
}

/// A textier release on GitHub, as the latest-release API describes it.
public struct Release: Sendable, Equatable {
    /// A file attached to a release.
    public struct Asset: Sendable, Equatable {
        public var name: String
        public var url: URL

        public init(name: String, url: URL) {
            self.name = name
            self.url = url
        }
    }

    public var version: AppVersion
    /// The release notes, in Markdown.
    public var notes: String
    /// The release's page.
    public var page: URL
    /// The app, zipped (`textier-<version>.zip`); nil when the release has none.
    public var archive: Asset?
    /// `SHA256SUMS.txt`, the archive's checksum among others.
    public var checksums: URL?

    public init(version: AppVersion, notes: String, page: URL, archive: Asset?, checksums: URL?) {
        self.version = version
        self.notes = notes
        self.page = page
        self.archive = archive
        self.checksums = checksums
    }

    /// Reads GitHub's JSON for a release; nil when it isn't one (a draft, a
    /// pre-release, or a tag that isn't a version).
    public init?(gitHubJSON text: String) {
        guard case .object(let entries)? = JSONValue.parse(text) else { return nil }
        func value(_ key: String, in entries: [JSONEntry]) -> JSONValue? { entries.last { $0.key == key }?.value }
        func string(_ key: String, in entries: [JSONEntry]) -> String? {
            if case .string(let string)? = value(key, in: entries) { string } else { nil }
        }
        if case .bool(true)? = value("draft", in: entries) { return nil }
        if case .bool(true)? = value("prerelease", in: entries) { return nil }
        guard let tag = string("tag_name", in: entries), let version = AppVersion(tag),
              let page = string("html_url", in: entries).flatMap(URL.init(string:))
        else { return nil }
        var archive: Asset?
        var checksums: URL?
        if case .array(let assets)? = value("assets", in: entries) {
            for case .object(let asset) in assets {
                guard let name = string("name", in: asset),
                      let url = string("browser_download_url", in: asset).flatMap(URL.init(string:)) else { continue }
                if name == "SHA256SUMS.txt" { checksums = url }
                // The release's own zip, or any zip of textier's.
                if name == "textier-\(version).zip" || (archive == nil && name.hasPrefix("textier-") && name.hasSuffix(".zip")) {
                    archive = Asset(name: name, url: url)
                }
            }
        }
        self.init(version: version, notes: string("body", in: entries) ?? "", page: page, archive: archive, checksums: checksums)
    }
}

/// What a check found.
public enum UpdateCheck: Sendable, Equatable {
    case upToDate
    case available(Release)
    /// Newer, but the user skipped this version: not offered unless asked.
    case skipped
}

/// What `latest` means for textier at `current`, with `skipped` the version the
/// user chose to skip.
public func updateCheck(current: AppVersion, latest: Release, skipped: AppVersion?) -> UpdateCheck {
    guard current < latest.version else { return .upToDate }
    return skipped == latest.version ? .skipped : .available(latest)
}

/// The SHA-256 `SHA256SUMS.txt` (`shasum -a 256` output) gives the file `name`,
/// lowercased.
public func checksum(of name: String, in sums: String) -> String? {
    for line in sums.split(whereSeparator: \.isNewline) {
        let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.count == 2 else { continue }
        // `shasum` marks a file read as binary with `*`.
        var file = parts[1].drop { $0 == " " }
        if file.first == "*" { file = file.dropFirst() }
        if file == name, parts[0].count == 64, parts[0].allSatisfy(\.isHexDigit) { return parts[0].lowercased() }
    }
    return nil
}

/// Whether an automatic check is due: a day since the last, or never, or the clock
/// went back.
public func isUpdateCheckDue(lastCheck: Date?, now: Date) -> Bool {
    guard let lastCheck else { return true }
    let elapsed = now.timeIntervalSince(lastCheck)
    return elapsed >= 86_400 || elapsed < 0
}
