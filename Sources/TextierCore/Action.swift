/// Something the user can do with a Match. The vocabulary is closed; config
/// files name Actions by their raw value.
public enum Action: String, Sendable, Equatable, CaseIterable {
    case copy
    case open
    case copyPretty = "copy-pretty"
    case openURL = "open-url"
    case openFile = "open-file"
}
