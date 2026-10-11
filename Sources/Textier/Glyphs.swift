import TextierCore

extension Glyph {
    /// The SF Symbol a Glyph is drawn as.
    var symbolName: String {
        switch self {
        case .json: "curlybraces"
        case .escapedJSON: "curlybraces.square"
        case .url: "link"
        case .datetime: "clock"
        case .filePath: "doc.text"
        case .logLevel: "flag"
        case .userPattern: "asterisk"
        case .plainText: "text.alignleft"
        }
    }
}

extension ActionBarItem {
    /// The SF Symbol beside the button's title.
    var symbolName: String {
        switch self {
        case .action(.copy): "doc.on.doc"
        case .action(.open): "macwindow"
        case .action(.copyPretty): "wand.and.stars"
        case .action(.openURL): "globe"
        case .action(.openFile): "chevron.left.forwardslash.chevron.right"
        case .popOut: "arrow.up.forward.app"
        case .copyWithLine: "list.number"
        }
    }
}
