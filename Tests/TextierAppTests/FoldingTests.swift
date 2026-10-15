import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor @Suite("Folding Raw JSON")
    struct FoldingTests {
        static let json = """
        {
          "a": {
            "b": 1,
            "c": [
              2,
              3
            ]
          },
          "d": 4
        }
        """

        /// A folding text view holding `text`, laid out at 400 pt wide.
        func textView(_ text: String = json) -> FoldingTextView {
            let textView = FoldingTextView.make(foldsJSON: true)
            textView.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
            textView.textContainer?.size = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
            textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.string = text
            return textView
        }

        /// The 1-based numbers of the lines shown, as the line numbers label them.
        func shownLines(_ textView: NSTextView) -> [Int] {
            let layoutManager = textView.layoutManager!
            layoutManager.ensureLayout(for: textView.textContainer!)
            let text = textView.string as NSString
            let starts = LineNumberRuler.lineStarts(in: text)
            var lines: [Int] = []
            layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) {
                _, _, _, glyphs, _ in
                let start = layoutManager.characterIndexForGlyph(at: glyphs.location)
                lines.append(starts.lastIndex { $0 <= start }! + 1)
            }
            return lines
        }

        func region(_ textView: FoldingTextView, opening key: String) -> FoldRegion {
            let open = (textView.string as NSString).range(of: key).location
            return textView.folding!.regions.first { $0.open > open }!
        }

        @Test func aFoldHidesItsBlocksLinesAndLeavesTheTextAlone() async throws {
            try await runInApp {
                let textView = textView()
                let folding = try #require(textView.folding)
                #expect(folding.regions.count == 3)
                #expect(shownLines(textView) == Array(1...10))

                folding.fold(region(textView, opening: #""a""#))
                // `"a": {⋯},` on line 2, then line 9: the numbers skip what's hidden.
                #expect(shownLines(textView) == [1, 2, 9, 10])
                #expect(textView.string == Self.json)

                // An inner fold under an outer one stays folded when the outer opens.
                folding.fold(region(textView, opening: #""c""#))
                folding.unfold(region(textView, opening: #""a""#))
                #expect(shownLines(textView) == [1, 2, 3, 4, 8, 9, 10])
            }
        }

        @Test func collapseAllFoldsAllButTheTopLevel() async throws {
            try await runInApp {
                let textView = textView()
                let folding = try #require(textView.folding)
                folding.foldAll()
                #expect(folding.folded == [region(textView, opening: #""a""#), region(textView, opening: #""c""#)])
                #expect(shownLines(textView) == [1, 2, 9, 10])
                folding.unfoldAll()
                #expect(shownLines(textView) == Array(1...10))
            }
        }

        @Test func editsAroundAFoldKeepItAndOnesIntoItExpandIt() async throws {
            try await runInApp {
                let textView = textView()
                let folding = try #require(textView.folding)
                let storage = try #require(textView.textStorage)
                folding.fold(region(textView, opening: #""a""#))

                // Before and after the block: it moves, and stays folded.
                storage.replaceCharacters(in: NSRange(location: 1, length: 0), with: "\n  \"z\": 0,")
                let end = (textView.string as NSString).range(of: "\"d\": 4").location
                storage.replaceCharacters(in: NSRange(location: end + 6, length: 0), with: ",\n  \"e\": 5")
                #expect(folding.folded == [region(textView, opening: #""a""#)])
                #expect(shownLines(textView) == [1, 2, 3, 10, 11, 12])
                // Colors (attributes only) don't touch it.
                storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: storage.length))
                #expect(folding.folded.count == 1)

                // An edit inside it expands it.
                let inside = (textView.string as NSString).range(of: "\"b\"").location
                storage.replaceCharacters(in: NSRange(location: inside, length: 0), with: " ")
                #expect(folding.folded.isEmpty)
                #expect(shownLines(textView).count == 12)

                // So does unbalancing its brackets.
                folding.fold(region(textView, opening: #""a""#))
                let open = region(textView, opening: #""a""#).open
                storage.replaceCharacters(in: NSRange(location: open, length: 1), with: "")
                #expect(folding.folded.isEmpty)
            }
        }

        @Test func theCursorMovingIntoAFoldExpandsItAndAnArrowStepsOverIt() async throws {
            try await runInApp {
                let textView = textView()
                let folding = try #require(textView.folding)
                let block = region(textView, opening: #""a""#)
                folding.fold(block)

                // → from before the "⋯": past it, still folded; ← back; ⌥→ by word too.
                @MainActor func move(_ selector: Selector) { textView.doCommand(by: selector) }
                textView.setSelectedRange(NSRange(location: block.hidden.location, length: 0))
                move(#selector(NSResponder.moveRight(_:)))
                #expect(textView.selectedRange().location == NSMaxRange(block.hidden))
                move(#selector(NSResponder.moveLeft(_:)))
                #expect(textView.selectedRange().location == block.hidden.location)
                textView.setSelectedRange(NSRange(location: block.open - 3, length: 0))
                move(#selector(NSResponder.moveWordRight(_:)))
                #expect(folding.foldHiding(textView.selectedRange().location) == nil)
                #expect(folding.isFolded(block))

                // Put inside it otherwise (Go to Line, Find): it opens.
                let inside = (textView.string as NSString).range(of: "\"b\"").location
                textView.setSelectedRange(NSRange(location: inside, length: 0))
                #expect(!folding.isFolded(block))
                #expect(textView.selectedRange().location == inside)

                // A selection over the whole fold leaves it folded.
                folding.fold(block)
                textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
                #expect(folding.isFolded(block))
            }
        }

        @Test func foldAndUnfoldAtTheCursor() async throws {
            try await runInApp {
                let textView = textView()
                let folding = try #require(textView.folding)
                let a = region(textView, opening: #""a""#), c = region(textView, opening: #""c""#)
                textView.setSelectedRange(NSRange(location: (textView.string as NSString).range(of: "2,").location, length: 0))

                textView.foldAtCursor()
                #expect(folding.folded == [c])
                // The cursor left the hidden text, for just after the bracket.
                #expect(textView.selectedRange().location == c.hidden.location)
                textView.foldAtCursor()
                #expect(folding.folded == [a, c])

                // The cursor moved out of `"a"` too, onto its line: that's the one that opens.
                textView.unfoldAtCursor()
                #expect(folding.folded == [c])
                // Nothing folded on or around the cursor's line: nothing opens.
                textView.unfoldAtCursor()
                #expect(folding.folded == [c])
                textView.setSelectedRange(NSRange(location: c.open, length: 0))
                textView.unfoldAtCursor()
                #expect(folding.folded.isEmpty)
            }
        }

        @Test func aLineWhereTwoBlocksOpenShowsAndTogglesBoth() async throws {
            try await runInApp {
                let textView = textView("[{\n  \"a\": 1\n}\n]")
                let folding = try #require(textView.folding)
                let outer = try #require(folding.regions.first), inner = try #require(folding.regions.last)
                let firstLine = NSRange(location: 0, length: 3)
                #expect(folding.regions(openingIn: firstLine) == [outer, inner])

                // Fold at the cursor takes the inner block; the line's chevron then opens it.
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.foldAtCursor()
                #expect(folding.folded == [inner])
                folding.toggleLine(opening: folding.regions(openingIn: firstLine))
                #expect(folding.folded.isEmpty)

                // With none folded, the chevron folds the outer one; the inner one is then
                // out of sight: not the line's, and Fold leaves it be.
                folding.toggleLine(opening: folding.regions(openingIn: firstLine))
                #expect(folding.folded == [outer])
                #expect(folding.regions(openingIn: firstLine) == [outer])
                textView.foldAtCursor()
                #expect(folding.folded == [outer])

                // Both folded: Unfold opens the outer one, not the inner one out of sight.
                folding.unfoldAll()
                folding.fold(inner)
                folding.fold(outer)
                textView.unfoldAtCursor()
                #expect(folding.folded == [inner])
            }
        }

        @Test func aFoldsRowHasTheChevronOfABlockOpeningAfterIt() async throws {
            try await runInApp {
                // After an edit: the next object opens on the line the first one closes on.
                let textView = textView("[\n  {\n    \"a\": 1\n  }, {\n    \"b\": 2\n  }\n]")
                let scrollView = NSScrollView(frame: textView.frame)
                scrollView.documentView = textView
                let ruler = LineNumberRuler(textView: textView)
                let folding = try #require(textView.folding)
                let first = folding.regions[1], second = folding.regions[2]
                folding.fold(first)
                // The row shows `{⋯}, {`: both blocks are its.
                #expect(ruler.regions(onRowFrom: first.open, to: first.close + 3) == [first, second])
                #expect(shownLines(textView) == [1, 2, 5, 6, 7])
            }
        }

        @Test func plainTextDoesntFold() async throws {
            try await runInApp {
                let textView = FoldingTextView.make(foldsJSON: false)
                textView.string = Self.json
                #expect(textView.folding?.regions.isEmpty == true)
            }
        }

        // MARK: Match Window

        func rawMatchWindow(_ app: AppHarness) throws -> (MatchWindowController, FoldingTextView) {
            app.capture(AppFixtures.monologLine)
            try app.runAction("Pop Out")
            let controller = try #require(app.matchWindows.last)
            controller.model.mode = .raw
            app.spin(0.2)
            let editor = try #require(controller.model.rawEditor)
            return (controller, editor)
        }

        @Test func theGutterAndThePlaceholderFoldAndExpand() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let (controller, editor) = try rawMatchWindow(app)
                let folding = try #require(editor.folding)
                let ruler = try #require(editor.enclosingScrollView?.verticalRulerView as? LineNumberRuler)
                let block = try #require(folding.regions.first { $0.open > 0 })
                #expect(ruler.ruleThickness > LineNumberRuler.chevronWidth)

                // A click on the block's line in the gutter folds it.
                let glyph = folding.glyphIndexForCharacter(at: block.open)
                let line = folding.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let inText = NSPoint(x: 0, y: line.midY + editor.textContainerOrigin.y)
                let inRuler = ruler.convert(inText, from: editor)
                #expect(ruler.regions(at: inRuler).first == block)
                ruler.mouseDown(with: click(at: ruler.convert(inRuler, to: nil), in: controller.window))
                #expect(folding.isFolded(block))

                // A click on its "⋯" expands it.
                let container = try #require(editor.textContainer)
                let placeholder = try #require(folding.placeholderRect(of: block, in: container))
                let point = NSPoint(x: placeholder.midX + editor.textContainerOrigin.x, y: placeholder.midY + editor.textContainerOrigin.y)
                editor.mouseDown(with: click(at: editor.convert(point, to: nil), in: controller.window))
                #expect(!folding.isFolded(block))

                // Anywhere on it: its left and right edges too.
                for x in [placeholder.minX + 1, placeholder.maxX - 1] {
                    folding.fold(block)
                    let edge = NSPoint(x: x + editor.textContainerOrigin.x, y: point.y)
                    #expect(folding.placeholder(at: NSPoint(x: x, y: placeholder.midY)) == block)
                    editor.mouseDown(with: click(at: editor.convert(edge, to: nil), in: controller.window))
                    #expect(!folding.isFolded(block))
                }
            }
        }

        func click(at point: NSPoint, in window: NSWindow) -> NSEvent {
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!
        }

        @Test func foldsShortcutWorksInTheEditor() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let (controller, editor) = try rawMatchWindow(app)
                let folding = try #require(editor.folding)
                controller.window.makeFirstResponder(editor)
                let block = try #require(folding.regions.last)
                editor.setSelectedRange(NSRange(location: block.hidden.location + 1, length: 0))
                let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.command, .option],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.window.windowNumber,
                    context: nil, characters: "[", charactersIgnoringModifiers: "[", isARepeat: false,
                    keyCode: UInt16(ShortcutKeys.codes["["]!)
                )!
                #expect(controller.window.performKeyEquivalent(with: event))
                #expect(folding.folded.count == 1)
            }
        }

        @Test func editingAroundAFoldKeepsItAndTheModelHasAllTheText() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let (controller, editor) = try rawMatchWindow(app)
                let folding = try #require(editor.folding)
                folding.foldAll()
                let folded = folding.folded
                #expect(!folded.isEmpty)
                let full = editor.string
                controller.window.makeFirstResponder(editor)

                // Typed at the end: recolored, the folds stay, the model has every line.
                let end = (editor.string as NSString).length
                editor.setSelectedRange(NSRange(location: end, length: 0))
                editor.insertText("\n", replacementRange: NSRange(location: end, length: 0))
                // After the reparse a moment later, too.
                app.spin(0.5)
                #expect(folding.folded == folded)
                #expect(controller.model.rawText == full + "\n")

                // Undone: the text and the folds as they were.
                editor.undoManager?.undo()
                app.spin(0.1)
                #expect(editor.string == full)
                #expect(folding.folded == folded)

                // Beautify or View Original put new text in: no folds.
                controller.model.viewOriginal()
                app.spin(0.2)
                #expect(folding.folded.isEmpty)
            }
        }

        // MARK: The card's Raw

        @Test func theCardsRawFoldsAndItsSearchExpandsWhatItFinds() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let content = try #require(app.panel.contentView)
                let modes = try #require(content.firstDescendant(of: NSSegmentedControl.self))
                modes.selectedSegment = 1
                _ = modes.sendAction(modes.action, to: modes.target)
                app.spin(0.3)
                let raw = try #require(content.firstDescendant(of: FoldingTextView.self) { !$0.isEditable })
                let folding = try #require(raw.folding)
                folding.foldAll()
                // A backtrace frame's "function", which the folds hide.
                let found = (raw.string as NSString).range(of: #""__call""#)
                #expect(folding.folded.contains { NSIntersectionRange($0.hidden, found).length > 0 })

                try #require(content.firstDescendant(of: NSSearchField.self)).type("function")
                app.spin(0.4)
                #expect(!folding.folded.contains { NSIntersectionRange($0.hidden, found).length > 0 })
            }
        }
    }
}
