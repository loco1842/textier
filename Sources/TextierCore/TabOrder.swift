import Foundation

/// `tabs` in the order the user arranged them by dragging: the Patterns named in
/// `order` first, in that order, then the others in the order they came, then
/// Plain Text, which stays last.
public func arrangedTabs(_ tabs: [InspectorTab], order: [String]) -> [InspectorTab] {
    let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    let patterns = tabs.filter { $0.id != .plainText }
    let arranged = patterns.filter { rank[$0.title] != nil }.sorted { rank[$0.title]! < rank[$1.title]! }
    let rest = patterns.filter { rank[$0.title] == nil }
    return arranged + rest + tabs.filter { $0.id == .plainText }
}

/// The arranged order after dragging the tab named `name` to `index` among the
/// Pattern tabs `shown`: those shown, rearranged, then the names arranged before
/// that aren't shown now, so they keep their place for next time.
public func arrangingTab(_ name: String, to index: Int, shown: [String], order: [String]) -> [String] {
    guard let from = shown.firstIndex(of: name) else { return order }
    var rearranged = shown
    rearranged.remove(at: from)
    rearranged.insert(name, at: min(max(index, 0), rearranged.count))
    return rearranged + order.filter { !shown.contains($0) }
}
