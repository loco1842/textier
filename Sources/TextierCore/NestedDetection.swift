import Foundation

/// The Matches to highlight in a Match Window showing `text`, a Match's own text
/// (or its beautified form). Detection runs again; a Match spanning all of `text`
/// is the shown Match itself, so its children take its place.
public func detectNested(in text: String, config: Config) -> [Match] {
    let whole = NSRange(text.startIndex..., in: text)
    return detect(text, config: config).flatMap { $0.range == whole ? $0.children : [$0] }
}
