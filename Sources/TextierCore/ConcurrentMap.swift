import Foundation

extension Array where Element: Sendable {
    /// `map` on every core, in chunks of `chunk`, the results in order. Fewer
    /// elements than a chunk are mapped in place: spreading them costs more than
    /// it saves.
    func concurrentMap<T: Sendable>(chunk: Int = 256, _ transform: @Sendable (Element) -> T) -> [T] {
        guard count > chunk else { return map(transform) }
        let chunks = (count + chunk - 1) / chunk
        return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            // Each chunk writes only its own elements.
            nonisolated(unsafe) let base = buffer.baseAddress!
            withoutActuallyEscaping(transform) { transform in
                DispatchQueue.concurrentPerform(iterations: chunks) { index in
                    let start = index * chunk
                    for position in start..<Swift.min(start + chunk, count) {
                        (base + position).initialize(to: transform(self[position]))
                    }
                }
            }
            initialized = count
        }
    }
}
