import Testing
import TextierCore

@Suite("Go to Line")
struct GoToLineTests {
    @Test func readsALineOrALineAndColumn() {
        #expect(LineTarget("120") == LineTarget(line: 120))
        #expect(LineTarget(" 120:15 ") == LineTarget(line: 120, column: 15))
        #expect(LineTarget("120 : 15") == LineTarget(line: 120, column: 15))
        for wrong in ["", "0", "-3", "12a", "1:0", "1:2:3", ":4", "4:"] {
            #expect(LineTarget(wrong) == nil, "\(wrong)")
        }
    }

    @Test func landsOnTheLineAndColumnOrTheNearestPlace() {
        // "ab\ncdef\n\ng": lines start at 0, 3, 8, 9.
        let starts = [0, 3, 8, 9]
        let length = 10
        #expect(LineTarget(line: 1).location(lineStarts: starts, length: length) == 0)
        #expect(LineTarget(line: 2, column: 3).location(lineStarts: starts, length: length) == 5)
        // Past a line's end: its end, before the line break.
        #expect(LineTarget(line: 2, column: 99).location(lineStarts: starts, length: length) == 7)
        // An empty line.
        #expect(LineTarget(line: 3, column: 5).location(lineStarts: starts, length: length) == 8)
        // Past the last line: the last line.
        #expect(LineTarget(line: 50).location(lineStarts: starts, length: length) == 9)
        #expect(LineTarget(line: 4, column: 9).location(lineStarts: starts, length: length) == 10)
    }
}
