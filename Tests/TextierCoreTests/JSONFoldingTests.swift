import Foundation
import Testing
@testable import TextierCore

@Suite("JSON folding")
struct JSONFoldingTests {
    /// Each region as the text from its opening bracket to its closing one.
    func folds(_ text: String) -> [String] {
        let ns = text as NSString
        return foldRegions(in: ns).map { ns.substring(with: NSRange(location: $0.open, length: $0.close - $0.open + 1)) }
    }

    @Test func objectsAndArraysOverSeveralLinesFold() {
        let text = """
        {
          "a": {
            "b": [1, 2],
            "c": [
              3
            ]
          },
          "d": {}
        }
        """
        #expect(folds(text) == [text, "{\n    \"b\": [1, 2],\n    \"c\": [\n      3\n    ]\n  }", "[\n      3\n    ]"])
    }

    @Test func bracketsInStringsDontCount() {
        let text = "{\n  \"a\": \"{ [ \\\" ]\",\n  \"b\": 1\n}"
        #expect(folds(text) == [text])
    }

    @Test func unbalancedTextFoldsWhatBalances() {
        // A closing bracket with nothing to close, and an object never closed.
        #expect(folds("]\n{\n  \"a\": [\n    1\n  ]\n") == ["[\n    1\n  ]"])
        // A "}" closes its "{", leaving the "[" opened after it unclosed.
        #expect(folds("{\n  \"a\": [\n}") == ["{\n  \"a\": [\n}"])
        // An unterminated string ends at its line.
        #expect(folds("{\n  \"a\": \"open\n  \"b\": 1\n}") == ["{\n  \"a\": \"open\n  \"b\": 1\n}"])
    }

    @Test func crlfLinesCountOnce() {
        let text = "{\r\n  \"a\": 1\r\n}"
        let regions = foldRegions(in: text as NSString)
        #expect(regions == [FoldRegion(open: 0, close: (text as NSString).length - 1)])
        #expect(regions[0].hidden == NSRange(location: 1, length: (text as NSString).length - 2))
    }
}
