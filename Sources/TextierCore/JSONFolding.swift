import Foundation

/// A block of JSON text that folds: an object or array whose closing bracket is on
/// a later line than its opening one. Offsets are UTF-16.
public struct FoldRegion: Sendable, Hashable {
    /// The opening bracket's offset.
    public var open: Int
    /// The closing bracket's offset.
    public var close: Int

    public init(open: Int, close: Int) {
        self.open = open
        self.close = close
    }

    /// What folding it hides: the text between its brackets.
    public var hidden: NSRange { NSRange(location: open + 1, length: close - open - 1) }
}

/// The blocks of `text` that fold, by opening bracket. Brackets in strings don't
/// count. Text that isn't balanced JSON (an edit in progress) folds what does
/// balance: a closing bracket closes the nearest open one of its kind, and those
/// opened after it never close; one with nothing to close is passed over. A line
/// break ends a string left open.
public func foldRegions(in text: NSString) -> [FoldRegion] {
    var regions: [FoldRegion] = []
    // Each open bracket: its character, its offset, and the line it's on.
    var open: [(bracket: unichar, offset: Int, line: Int)] = []
    var line = 0
    var inString = false
    var escaped = false
    let length = text.length
    var index = 0
    while index < length {
        let character = text.character(at: index)
        defer { index += 1 }
        if isLineBreak(character, at: index, in: text) {
            line += 1
            inString = false
            escaped = false
            continue
        }
        if inString {
            if escaped {
                escaped = false
            } else if character == 0x5C {  // \
                escaped = true
            } else if character == 0x22 {  // "
                inString = false
            }
            continue
        }
        switch character {
        case 0x22:
            inString = true
        case 0x7B, 0x5B:  // { [
            open.append((character, index, line))
        case 0x7D, 0x5D:  // } ]
            let partner: unichar = character == 0x7D ? 0x7B : 0x5B
            guard let match = open.lastIndex(where: { $0.bracket == partner }) else { continue }
            let opened = open[match]
            open.removeSubrange(match...)
            if line > opened.line { regions.append(FoldRegion(open: opened.offset, close: index)) }
        default:
            break
        }
    }
    return regions.sorted { $0.open < $1.open }
}

/// A line break as the text system breaks lines (a CR LF counts once, at its LF).
private func isLineBreak(_ character: unichar, at index: Int, in text: NSString) -> Bool {
    switch character {
    case 0x0A, 0x85, 0x2028, 0x2029: true
    case 0x0D: index + 1 >= text.length || text.character(at: index + 1) != 0x0A
    default: false
    }
}
