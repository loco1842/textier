import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppHarness {
    /// Double-clicks the row at `path` in `outline`. NSTableView ignores synthetic
    /// clicks while its window isn't key, which it isn't whenever another app is
    /// frontmost, so this goes through the viewer's double-click instead.
    func doubleClick(row path: String, in outline: NSOutlineView) throws {
        outline.viewer.doubleClick(try #require(outline.node(keyPath: path)))
        spin()
    }
}

extension NSOutlineView {
    /// The row cell of the node at `path`, once it's shown.
    func cell(keyPath path: String) -> JSONRowCell? {
        guard let row = row(keyPath: path) else { return nil }
        return view(atColumn: 0, row: row, makeIfNecessary: true) as? JSONRowCell
    }
}

extension NSView {
    /// Every view of type `type` inside this one, depth first.
    func descendants<T: NSView>(of type: T.Type, where test: (T) -> Bool = { _ in true }) -> [T] {
        subviews.flatMap { view -> [T] in
            ((view as? T).map { test($0) ? [$0] : [] } ?? []) + view.descendants(of: type, where: test)
        }
    }

    func firstDescendant<T: NSView>(of type: T.Type, where test: (T) -> Bool = { _ in true }) -> T? {
        descendants(of: type, where: test).first
    }
}

extension NSSearchField {
    /// Types `text` into the field, as the keyboard would, telling its delegate.
    @MainActor
    func type(_ text: String) {
        stringValue = text
        delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: self))
    }
}

extension NSTextField {
    /// The text color where `text` first appears in the label.
    func color(at text: String) -> NSColor? {
        let range = (stringValue as NSString).range(of: text)
        guard range.location != NSNotFound else { return nil }
        return attributedStringValue.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }
}

extension AppTests {
    @MainActor
    @Suite("The JSON Viewer in the Inspector")
    struct JSONViewerTests {
        @Test func theTreeKeepsKeyOrderAndOpensBacktraceFrames() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())

                let root = try #require(outline.node(keyPath: ""))
                #expect(root.children.map(\.keyText) == [
                    "url", "repository", "method", "scope_count", "caller_file", "caller_line", "caller_function",
                    "backtrace",
                ])
                #expect(outline.isItemExpanded(try #require(outline.node(keyPath: "backtrace[0]"))))
                #expect(outline.node(keyPath: "backtrace[4].function") != nil)
            }
        }

        @Test func rowsReadAsKeyColonValueWithTheirTypeAtTheRight() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())

                #expect(outline.cell(keyPath: "method")?.label.stringValue == "method: where")
                #expect(outline.cell(keyPath: "method")?.typeLabel.stringValue == "”")
                #expect(outline.cell(keyPath: "caller_line")?.typeLabel.stringValue == "#")
                #expect(outline.cell(keyPath: "caller_line")?.typeLabel.toolTip == "Number")
                // An open container gives its size, a closed one a preview.
                #expect(outline.cell(keyPath: "")?.label.stringValue == "root  8 keys")
                #expect(outline.cell(keyPath: "")?.typeLabel.stringValue == "{}")
                #expect(outline.cell(keyPath: "backtrace")?.typeLabel.stringValue == "[]")
                let frame = try #require(outline.node(keyPath: "backtrace[1]"))
                outline.collapseItem(frame)
                #expect(outline.cell(keyPath: "backtrace[1]")?.label.stringValue
                    == "1: { SendLoginFromNewIPEmailToPlayer.php:118 › findActiveTemplate() }")
                outline.expandItem(frame)
                #expect(outline.cell(keyPath: "backtrace[1]")?.label.stringValue == "1: 3 keys")
            }
        }

        @Test func aPathUnderHomeShowsWithATildeButKeepsItsFullValue() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                outline.viewer.homeDirectory = "/Users/mac"
                outline.reloadData()

                let cell = try #require(outline.cell(keyPath: "caller_file"))
                #expect(cell.label.stringValue.hasPrefix("caller_file: ~/Documents/Projects/dv/"))
                #expect(cell.label.toolTip?.hasSuffix(AppFixtures.callerFile) == true)
                outline.viewer.copyValue(of: try #require(outline.node(keyPath: "caller_file")))
                #expect(app.copied == AppFixtures.callerFile)
            }
        }

        @Test func aLongValueIsOneLineUntilSelectedThenWrapsUpToALimit() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let long = String(repeating: "abcdefghij", count: 100)
                app.capture(#"{"short": "x", "long": "\#(long)"}"#)
                app.spin(0.2)
                let outline = try #require(app.outlineView())
                let oneLine = outline.rect(ofRow: try #require(outline.row(keyPath: "short"))).height
                let longRow = try #require(outline.row(keyPath: "long"))
                #expect(outline.rect(ofRow: longRow).height == oneLine)
                #expect(outline.cell(keyPath: "long")?.label.maximumNumberOfLines == 1)

                outline.selectRowIndexes([longRow], byExtendingSelection: false)
                app.spin(0.3)
                let lineHeight = NSLayoutManager().defaultLineHeight(for: JSONColoring.font)
                #expect(outline.rect(ofRow: longRow).height == oneLine + CGFloat(JSONViewer.maximumValueLines - 1) * lineHeight)
                #expect(outline.cell(keyPath: "long")?.label.maximumNumberOfLines == JSONViewer.maximumValueLines)

                outline.selectRowIndexes([try #require(outline.row(keyPath: "short"))], byExtendingSelection: false)
                app.spin(0.3)
                #expect(outline.rect(ofRow: longRow).height == oneLine)
            }
        }

        @Test func theSelectedRowFitsItsWrappedValueAtAnyWidth() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.panel.setContentSize(NSSize(width: 1800, height: 700))
                app.capture(AppFixtures.monologLine)
                try app.select("json", 0)
                app.spin(0.3)
                let outline = try #require(app.outlineView())
                let oneLine = outline.rect(ofRow: try #require(outline.row(keyPath: "method"))).height
                let row = try #require(outline.row(keyPath: "caller_file"))
                outline.selectRowIndexes([row], byExtendingSelection: false)

                for divider in stride(from: 500.0, through: 1400, by: 47) {
                    app.controller.splitView.setPosition(divider, ofDividerAt: 0)
                    app.spin(0.1)
                    app.panel.contentView?.layoutSubtreeIfNeeded()
                    let label = try #require(outline.cell(keyPath: "caller_file")?.label)
                    let needed = try #require(label.cell).cellSize(
                        forBounds: NSRect(x: 0, y: 0, width: label.frame.width, height: 10_000)
                    ).height
                    let lineHeight = NSLayoutManager().defaultLineHeight(for: JSONColoring.font)
                    let lines = min(JSONViewer.maximumValueLines, Int((needed / lineHeight - 0.25).rounded(.up)))
                    #expect(
                        outline.rect(ofRow: row).height == oneLine + CGFloat(lines - 1) * lineHeight,
                        "at width \(outline.bounds.width)"
                    )
                }
            }
        }

        @Test func linesRunDownTheOpenLevelsARowSitsIn() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                func guides(_ path: String) throws -> Int {
                    let row = try #require(outline.row(keyPath: path))
                    let view = try #require(outline.rowView(atRow: row, makeIfNecessary: true))
                    return (view.value(forKey: "guideCount") as? Int) ?? -1
                }
                #expect(try guides("") == 0)
                #expect(try guides("url") == 1)
                #expect(try guides("backtrace[0].file") == 3)

                // Every row's lines sit at the same places, under its parents' disclosure
                // triangles, whether the row has a triangle of its own or not.
                func positions(_ path: String) throws -> [CGFloat] {
                    let row = try #require(outline.row(keyPath: path))
                    return try #require(outline.rowView(atRow: row, makeIfNecessary: true) as? ThemedRowView).guides
                }
                func triangle(_ path: String) throws -> CGFloat {
                    outline.frameOfOutlineCell(atRow: try #require(outline.row(keyPath: path))).midX
                }
                let leaf = try positions("backtrace[0].file")
                let container = try positions("backtrace[1]")
                #expect(Array(leaf.prefix(2)) == container)
                #expect(leaf == [try triangle(""), try triangle("backtrace"), try triangle("backtrace[0]")].map { $0.rounded(.down) })
            }
        }

        @Test func textAndTheSelectedRowTakeTheThemesColors() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("json", 0)
                let outline = try #require(app.outlineView())
                func hex(_ color: NSColor?) -> String? {
                    var hex: String?
                    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { hex = color?.hexString }
                    return hex
                }
                let dark = Theme.githubDark
                let foreground = try #require(NSColor(hex: dark.foreground))

                // The tree sits on the Inspector's own card, not the theme's near-black.
                #expect(outline.backgroundColor.alphaComponent == 0)

                // A size like `8 keys` is the theme's foreground, faded, not a system gray.
                let label = try #require(outline.cell(keyPath: "")?.label)
                #expect(hex(label.color(at: "8 keys")) == foreground.withAlphaComponent(0.6).hexString)

                // A selected row washes in the theme's foreground, and its text keeps its colors.
                let root = try #require(outline.row(keyPath: ""))
                outline.selectRowIndexes([root], byExtendingSelection: false)
                let rowView = try #require(outline.rowView(atRow: root, makeIfNecessary: true))
                #expect(rowView.interiorBackgroundStyle == .normal)
                #expect(hex(NSColor.themeSelection(light: .githubLight, dark: dark)) == foreground.withAlphaComponent(0.16).hexString)
            }
        }

        @Test func searchShowsWhatMatchesAndTheContainersLeadingToIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer

                viewer.search("LINE")
                // caller_line and each frame's line, under root, backtrace and the frames.
                #expect(viewer.matchCount == 6)
                #expect(outline.numberOfRows == 1 + 1 + 1 + 5 + 5)
                #expect(outline.node(keyPath: "method") == nil)
                #expect(outline.node(keyPath: "backtrace[3].line") != nil)
                let row = try #require(outline.row(keyPath: "caller_line"))
                let rowView = try #require(outline.rowView(atRow: row, makeIfNecessary: true) as? ThemedRowView)
                #expect(rowView.isMatch)
                let backtraceRow = try #require(outline.row(keyPath: "backtrace"))
                let backtrace = try #require(outline.rowView(atRow: backtraceRow, makeIfNecessary: true) as? ThemedRowView)
                #expect(!backtrace.isMatch)

                viewer.search("no such thing")
                #expect(viewer.matchCount == 0)
                #expect(outline.numberOfRows == 0)
            }
        }

        @Test func clearingTheSearchOpensTheTreeAsItWasAndKeepsTheSelection() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer
                outline.collapseItem(try #require(outline.node(keyPath: "backtrace[1]")))
                let rowsBefore = outline.numberOfRows

                viewer.search("shouldQueue")
                let found = try #require(outline.node(keyPath: "backtrace[2].function"))
                outline.selectRowIndexes([outline.row(forItem: found)], byExtendingSelection: false)

                viewer.search("")
                #expect(outline.numberOfRows == rowsBefore)
                #expect(!outline.isItemExpanded(try #require(outline.node(keyPath: "backtrace[1]"))))
                #expect(outline.isItemExpanded(try #require(outline.node(keyPath: "backtrace[0]"))))
                #expect(viewer.selectedNode === found)
            }
        }

        @Test func aSearchThatHidesTheSelectedRowClearsThePathBarUntilItsShownAgain() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer
                let file = try #require(outline.node(keyPath: "backtrace[0].file"))
                viewer.select(file)
                var reported: [JSONNode?] = []
                viewer.onSelectionChange = { reported.append($0) }

                viewer.search("line")
                #expect(viewer.selectedNode == nil)
                #expect(reported.last.map { $0 == nil } == true)

                viewer.search("")
                #expect(viewer.selectedNode === file)
                #expect(reported.last.map { $0 === file } == true)
            }
        }

        @Test func aJSONPathQueryShowsItsResultsAndWhatLeadsToThem() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer

                viewer.search("$.backtrace[*].line")
                #expect(viewer.searchError == nil)
                #expect(viewer.matchCount == 5)
                #expect(outline.numberOfRows == 1 + 1 + 5 + 5)
                #expect(outline.node(keyPath: "caller_line") == nil)

                // A matched frame shows closed, with its preview, and opens to all of it.
                viewer.search("$.backtrace[?@.line > 500]")
                #expect(viewer.matchCount == 2)
                let frame = try #require(outline.node(keyPath: "backtrace[2]"))
                #expect(!outline.isItemExpanded(frame))
                outline.expandItem(frame)
                #expect(outline.node(keyPath: "backtrace[2].function") != nil)

                viewer.copyResults()
                #expect(app.copied == JSONValue.array([
                    try #require(outline.node(keyPath: "backtrace[2]")).value,
                    try #require(outline.node(keyPath: "backtrace[3]")).value,
                ]).prettyPrinted)
            }
        }

        @Test func aJSONPathMistakeSaysWhereAndLeavesTheTreeAlone() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer
                let rows = outline.numberOfRows

                viewer.search("$.backtrace[")
                #expect(viewer.searchError == "Expected a selector at 13")
                #expect(viewer.matchCount == 0)
                #expect(outline.numberOfRows == rows)

                viewer.search("")
                #expect(viewer.searchError == nil)

                // Typing a query on from a valid one, the tree keeps its last results
                // while the query is broken, instead of jumping back to everything.
                viewer.search("$..line")
                let filtered = outline.numberOfRows
                #expect(filtered < rows)
                viewer.search("$..line[")
                #expect(viewer.searchError != nil)
                #expect(outline.numberOfRows == filtered)
                viewer.search("$..function")
                #expect(viewer.searchError == nil && viewer.matchCount == 5)
                viewer.search("")
                #expect(outline.numberOfRows == rows)
            }
        }

        @Test func searchDoesntParseEscapedJSONInline() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(#"{"payload": "{\"inner\": 1}", "other": "x"}"#)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer
                let payload = try #require(outline.node(keyPath: "payload"))
                #expect(payload.escapedJSON != nil)

                // The escaped text matches as the string it is, unopened.
                viewer.search("inner")
                #expect(viewer.matchCount == 1)
                #expect(!viewer.isParsedInline(payload))
                viewer.search("")
                #expect(!viewer.isParsedInline(payload))

                // Parsed inline before the search, it's parsed inline after.
                viewer.toggleInline(payload)
                viewer.search("other")
                viewer.search("")
                #expect(viewer.isParsedInline(payload))
            }
        }

        @Test func escapedJSONTheSearchShowsStillParsesInline() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(#"{"payload": "{\"inner\": 1}", "other": "x"}"#)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer

                for query in ["payload", "$.payload"] {
                    viewer.search(query)
                    let payload = try #require(outline.node(keyPath: "payload"))
                    #expect(outline.isExpandable(payload))
                    try app.doubleClick(row: "payload", in: outline)
                    #expect(viewer.isParsedInline(payload))
                    #expect(outline.node(keyPath: "payload.inner") != nil)
                    viewer.toggleInline(payload)
                    #expect(!viewer.isParsedInline(payload))
                    viewer.search("")
                }
            }
        }

        @Test func aKeyTwiceIsTwoResultsOfAQuery() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(#"{"a": 1, "a": 2}"#)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer

                viewer.search("$.*")
                #expect(viewer.matchCount == 2)
                #expect(viewer.pathResults.count == 2 && viewer.pathResults[0] !== viewer.pathResults[1])
                viewer.copyResults()
                #expect(app.copied == JSONValue.array([.number("1"), .number("2")]).prettyPrinted)
            }
        }

        @Test func everyLineBreakInAValueShowsAsOneMark() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(#"{"s": "a\r\nb\rc\nd e"}"#)
                let outline = try #require(app.outlineView())

                #expect(outline.cell(keyPath: "s")?.label.stringValue == "s: a⏎b⏎c⏎d⏎e")
            }
        }

        @Test func aHugeValueShowsItsStartAndCopiesWhole() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let long = String(repeating: "abcdefghij", count: 1_000)
                app.capture(#"{"long": "\#(long)"}"#)
                let outline = try #require(app.outlineView())
                let start = String(long.prefix(JSONViewer.shownCharacters)) + "…"

                let cell = try #require(outline.cell(keyPath: "long"))
                #expect(cell.label.stringValue == "long: " + start)
                #expect(cell.label.toolTip == start)
                outline.viewer.copyValue(of: try #require(outline.node(keyPath: "long")))
                #expect(app.copied == long)
            }
        }

        @Test func theSearchFieldFiltersTheTreeAMomentAfterTyping() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                let field = try #require(app.panel.contentView?.firstDescendant(of: NSSearchField.self))

                field.type("line")
                app.spin(0.3)
                #expect(outline.viewer.query == "line")
                #expect(outline.viewer.matchCount == 6)
            }
        }

        @Test func escClearsTheSearchFieldAndLeavesThePanelOpen() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let field = try #require(app.panel.contentView?.firstDescendant(of: NSSearchField.self))
                app.panel.makeFirstResponder(field)
                field.type("where")
                app.spin(0.3)

                let editor = try #require(app.panel.firstResponder as? NSTextView)
                editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
                app.spin(0.3)
                #expect(field.stringValue.isEmpty)
                #expect(try #require(app.outlineView()).viewer.query.isEmpty)
                #expect(app.panel.isVisible)
            }
        }

        @Test func commandFPutsTheCursorInTheSearchField() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let field = try #require(app.panel.contentView?.firstDescendant(of: NSSearchField.self))
                let finder = try #require(field.delegate as? JSONSearchField.Coordinator)
                #expect(app.panel.firstResponder === app.textView)

                #expect(finder.focusIfFind(app.keyEvent("f", modifiers: .command)))
                #expect((app.panel.firstResponder as? NSTextView)?.delegate === field)
                #expect(!finder.focusIfFind(app.keyEvent("g", modifiers: .command)))
            }
        }

        @Test func thePathBarStepsFromTheRootToTheSelectedRow() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())

                let steps = try #require(outline.node(keyPath: "backtrace[0].file")).pathSteps
                #expect(steps.map { $0.separator + $0.label } == ["$", ".backtrace", "[0]", ".file"])
                outline.viewer.select(steps[2].node)
                #expect(outline.viewer.selectedNode === steps[2].node)
            }
        }

        @Test func rawShowsLineNumbersAndMarksWhatTheSearchFinds() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let content = try #require(app.panel.contentView)
                let modes = try #require(content.firstDescendant(of: NSSegmentedControl.self))
                modes.selectedSegment = 1
                _ = modes.sendAction(modes.action, to: modes.target)
                app.spin(0.3)
                let raw = try #require(content.firstDescendant(of: NSTextView.self) { !$0.isEditable && $0.string.hasPrefix("{") })
                #expect(raw.enclosingScrollView?.verticalRulerView is LineNumberRuler)

                try #require(content.firstDescendant(of: NSSearchField.self)).type("function")
                app.spin(0.4)
                let first = (raw.string as NSString).range(of: "function")
                let mark = raw.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: first.location, effectiveRange: nil)
                #expect(mark != nil)
                let elsewhere = raw.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil)
                #expect(elsewhere == nil)
            }
        }

        @Test func aJSONMatchWindowHasOneTreeRawSwitch() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.runAction("Pop Out")
                let window = try #require(app.matchWindows.last).window
                app.spin(0.2)
                let switches = try #require(window.contentView).descendants(of: NSSegmentedControl.self)
                #expect(switches.count == 1)
                #expect(switches.first.map { $0.label(forSegment: 0) } == "Tree")
            }
        }

        @Test func noContextMenuInTheTree() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())

                #expect(outline.menu == nil)
                let row = try #require(outline.row(keyPath: "url"))
                let cell = outline.frameOfCell(atColumn: 0, row: row)
                let event = app.mouseEvent(.rightMouseDown, at: outline.convert(NSPoint(x: cell.midX, y: cell.midY), to: nil))
                #expect(outline.menu(for: event) == nil)
            }
        }

        @Test func nodeActionsCopyKeyPathsAndValuesAndExpandSubtrees() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer

                let file = try #require(outline.node(keyPath: "backtrace[0].file"))
                outline.selectRowIndexes([outline.row(forItem: file)], byExtendingSelection: false)
                #expect(viewer.selectedNode === file)
                #expect(file.keyPathString == "backtrace[0].file")

                let frame = try #require(outline.node(keyPath: "backtrace[1]"))
                viewer.copyValue(of: frame)
                #expect(app.copied == """
                {
                  "file": "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php",
                  "line": 118,
                  "function": "findActiveTemplate"
                }
                """)

                let backtrace = try #require(outline.node(keyPath: "backtrace"))
                outline.collapseItem(backtrace, collapseChildren: true)
                #expect(outline.node(keyPath: "backtrace[0]") == nil)
                outline.expandItem(backtrace, expandChildren: true)
                #expect(outline.node(keyPath: "backtrace[4].file") != nil)
            }
        }

        @Test func linkValuesOpenTheirFirstActionOnDoubleClick() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())

                try app.doubleClick(row: "url", in: outline)
                #expect(app.openedURLs == [URL(string: "http://app.bo.test/player/api/v1/signin")!])
                try app.doubleClick(row: "backtrace[0].file", in: outline)
                #expect(app.openedFiles.first?.path.hasSuffix("EmailTemplateService.php") == true)
            }
        }

        @Test func aBacktraceFrameOpensAtItsLineOnDoubleClickAndCallerFileAtTheTop() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())

                try app.doubleClick(row: "backtrace[0].file", in: outline)
                try app.doubleClick(row: "backtrace[2].file", in: outline)
                try app.doubleClick(row: "caller_file", in: outline)
                #expect(app.openedFiles == [
                    FileLocation(path: AppFixtures.backtraceFile, line: 80),
                    FileLocation(path: AppFixtures.dispatcherFile, line: 603),
                    FileLocation(path: AppFixtures.callerFile, line: nil),
                ])
            }
        }

        @Test func copyWithLineIsOnlyOnPairedFileValuesAndCopyValueKeepsThePath() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer

                let frame = try #require(outline.node(keyPath: "backtrace[2].file"))
                #expect(frame.pairedLine == 603)
                viewer.copyWithLine(of: frame)
                #expect(app.copied == AppFixtures.dispatcherFile + ":603")
                viewer.copyValue(of: frame)
                #expect(app.copied == AppFixtures.dispatcherFile)

                for path in ["caller_file", "backtrace[2].line", "backtrace[2].function", "backtrace[2]", "url"] {
                    #expect(try #require(outline.node(keyPath: path)).pairedLine == nil, "\(path)")
                }
            }
        }

        @Test func aFrameInsideEscapedJSONParsedInlinePairsToo() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(#"{"context":"{\"backtrace\":[{\"file\":\"/app/Http/Kernel.php\",\"line\":\"42\"}]}"}"#)
                let outline = try #require(app.outlineView())

                let context = try #require(outline.node(keyPath: "context"))
                outline.viewer.toggleInline(context)
                outline.expandItem(context, expandChildren: true)
                let file = try #require(outline.node(keyPath: "context.backtrace[0].file"))
                #expect(file.pairedLine == 42)
                try app.doubleClick(row: "context.backtrace[0].file", in: outline)
                #expect(app.openedFiles == [FileLocation(path: "/app/Http/Kernel.php", line: 42)])
            }
        }

        @Test func aFrameInAMatchWindowsTreePairsToo() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.runAction("Pop Out")
                app.spin(0.2)
                let window = try #require(app.matchWindows.last)
                let outline = try #require(app.outlineView(in: window.window))

                try app.doubleClick(row: "backtrace[4].file", in: outline)
                #expect(app.openedFiles == [FileLocation(path: AppFixtures.dispatcherFile, line: 479)])
            }
        }

        @Test func escapedJSONParsesInlineCollapsesBackAndOpensAMatchWindow() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(#"{"payload":"{\"a\":1,\"b\":[1,2]}"}"#)
                let outline = try #require(app.outlineView())
                let viewer = outline.viewer

                let payload = try #require(outline.node(keyPath: "payload"))
                #expect(payload.escapedJSON != nil)
                viewer.toggleInline(payload)
                #expect(viewer.isParsedInline(payload))
                #expect(outline.node(keyPath: "payload.b") != nil)
                viewer.toggleInline(payload)
                #expect(!viewer.isParsedInline(payload))

                guard case .string(let string) = payload.value else { return }
                Action.open.perform(on: Match(
                    range: NSRange(string.startIndex..., in: string), text: string, patternName: "escaped-json", patternIndex: 1,
                    actions: [.open]
                ))
                app.spin(0.2)
                let window = try #require(app.matchWindows.last)
                #expect(window.model.entry.text == #"{"a":1,"b":[1,2]}"#)
                #expect(app.outlineView(in: window.window)?.node(keyPath: "b[1]") != nil)
            }
        }
    }

    @MainActor
    @Suite("Syntax coloring")
    struct ThemeTests {
        /// The Raw string for the Monolog JSON, with the given themes.
        func coloredText(light: Theme, dark: Theme) -> NSAttributedString {
            JSONColoring.attributedString(
                JSONValue.parse(AppFixtures.jsonPayload)!.prettyPrinted, light: light, dark: dark
            )
        }

        func color(of token: String, in colored: NSAttributedString, appearance: NSAppearance.Name) -> String? {
            let range = (colored.string as NSString).range(of: token)
            return hex(colored.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor, in: appearance)
        }

        @Test func textModeColorsKeysStringsAndNumbersWithGitHubThemesPerAppearance() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let colored = coloredText(light: app.store.lightTheme, dark: app.store.darkTheme)

                let key = color(of: #""method""#, in: colored, appearance: .aqua)
                let string = color(of: #""where""#, in: colored, appearance: .aqua)
                let number = color(of: "118", in: colored, appearance: .aqua)
                #expect(Set([key, string, number]).count == 3)
                #expect(string == Theme.githubLight.style(for: .string).color)
                #expect(color(of: #""where""#, in: colored, appearance: .darkAqua) == Theme.githubDark.style(for: .string).color)
            }
        }

        @Test func rawShowsURLsAndFilePathsAsPlainStringsNotLinks() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let colored = coloredText(light: app.store.lightTheme, dark: app.store.darkTheme)

                let whole = NSRange(location: 0, length: colored.length)
                var links = 0
                colored.enumerateAttribute(.link, in: whole) { value, _, _ in if value != nil { links += 1 } }
                #expect(links == 0)
                let url = (colored.string as NSString).range(of: "http://app.bo.test")
                #expect(colored.attribute(.underlineStyle, at: url.location, effectiveRange: nil) == nil)
                #expect(color(of: "http://app.bo.test", in: colored, appearance: .aqua) == Theme.githubLight.style(for: .string).color)
            }
        }

        @Test func treeValuesUseTheThemesColors() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let outline = try #require(app.outlineView())

                let label = try #require(outline.cell(keyPath: "method")?.label)
                #expect(hex(label.color(at: "where"), in: .aqua) == Theme.githubLight.style(for: .string).color)
                #expect(hex(label.color(at: "where"), in: .darkAqua) == Theme.githubDark.style(for: .string).color)
                #expect(hex(label.color(at: "method"), in: .darkAqua) == Theme.githubDark.style(for: .key).color)
            }
        }
    }
}
