import AppKit
import Testing
import TextierCore
@testable import Textier

/// A color's sRGB hex in one appearance.
@MainActor
func hex(_ color: NSColor?, in appearance: NSAppearance.Name) -> String? {
    var result: String?
    NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return }
        result = String(
            format: "#%02x%02x%02x", Int(round(rgb.redComponent * 255)), Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
    return result
}

extension AppHarness {
    /// The fill and solid color of the Input's pill at the start of `text`.
    func tint(at text: String) -> (background: NSColor?, solid: NSColor?) {
        let location = range(of: text).location
        guard let pill = textView.pills.last(where: { NSLocationInRange(location, $0.range) }) else { return (nil, nil) }
        return (pill.fill, NSColor(patternColor: pill.color, role: \.solid))
    }
}

extension AppTests {
    @MainActor
    @Suite("Pattern colors in the Input")
    struct ColorTests {
        @Test func eachPatternIsTintedInItsOwnPaletteColorAndTabsCarryIt() async throws {
            try await runInApp {
                var config = Config.default
                config.patterns[5].enabled = true  // log level
                config.patterns[5].colorRules = []  // its palette color, not its Color Rules'
                let app = try AppHarness(config: String(decoding: ConfigFile.encode(config), as: UTF8.self))
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                let datetime = hex(app.tint(at: "2026-10-07").solid, in: .aqua)
                let json = hex(app.tint(at: #"{"url""#).solid, in: .aqua)
                let level = hex(app.tint(at: "WARNING").solid, in: .aqua)
                #expect(datetime == "#6e56cf")
                #expect(json == "#ffc53d")
                #expect(level == "#e5484d")
                #expect(app.tint(at: "2026-10-07").background != nil)
                #expect(app.inspection.tabs.first { $0.title == "datetime" }?.color?.light == "#6e56cf")
            }
        }

        @Test func aV1ConfigWithoutColorsGetsThePaletteAndNoWarnings() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                { "patterns": [
                  { "name": "json", "builtin": "json", "enabled": true, "actions": ["open", "copy-pretty", "copy"] },
                  { "name": "datetime", "regex": "\\d{4}-\\d{2}-\\d{2}", "enabled": true, "actions": ["copy"] }
                ] }
                """#)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.model.warnings.isEmpty)
                #expect(hex(app.tint(at: "2026-10-07").solid, in: .aqua) == "#6e56cf")
            }
        }

        @Test func aPairedColorFollowsTheAppearanceAndASingleOneFillsBoth() async throws {
            try await runInApp {
                var config = Config.default
                config.patterns[3].color = PatternColor(light: "#0550ae", dark: "#79c0ff")  // datetime
                config.patterns[0].color = PatternColor("#e5c07b")  // json
                let app = try AppHarness(config: String(decoding: ConfigFile.encode(config), as: UTF8.self))
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                let datetime = app.tint(at: "2026-10-07").solid
                #expect(hex(datetime, in: .aqua) == "#0550ae")
                #expect(hex(datetime, in: .darkAqua) == "#79c0ff")
                let json = app.tint(at: #"{"url""#).solid
                #expect(hex(json, in: .aqua) == "#e5c07b")
                #expect(hex(json, in: .darkAqua) == "#e5c07b")
            }
        }

        @Test func anInvalidColorWarnsInTheFooterAndFallsBackToThePalette() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                { "patterns": [
                  { "name": "datetime", "regex": "\\d{4}-\\d{2}-\\d{2}", "actions": ["copy"], "color": "orange" }
                ] }
                """#)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.model.warnings.contains { $0.contains("datetime") && $0.contains("color") })
                #expect(hex(app.tint(at: "2026-10-07").solid, in: .aqua) == "#6e56cf")
            }
        }

        @Test func aUserPatternWithoutAColorGetsOneNoOtherPatternUses() async throws {
            try await runInApp {
                var config = Config.default
                config.patterns.append(Pattern(name: "ticket", regex: "SCOPE LEAK", actions: [.copy]))
                let app = try AppHarness(config: String(decoding: ConfigFile.encode(config), as: UTF8.self))
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                let ticketTab = app.inspection.tabs.first { $0.title == "ticket" }
                let ticket = try #require(ticketTab?.color)
                let others = app.inspection.tabs.filter { $0.title != "ticket" }.compactMap(\.color)
                #expect(!others.contains(ticket))
                #expect(hex(app.tint(at: "SCOPE LEAK").solid, in: .aqua) == ticket.light)
            }
        }
    }

    @MainActor
    @Suite("Clicks and Highlighting in the Input")
    struct InputTests {
        @Test func aClickOnAMatchOpensItInTheInspectorAndPlacesTheCursor() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                #expect(app.selectedTabTitle == "json")

                app.click(onText: "11:17:10")

                #expect(app.selectedTabTitle == "datetime")
                #expect(app.model.selectedEntry?.text == "2026-10-07 11:17:10")
                #expect(app.copied == nil)
                // The cursor stays where the click put it, so editing inside a Match works.
                #expect(app.textView.selectedRange().length == 0)
                #expect(NSLocationInRange(app.textView.selectedRange().location, app.range(of: "11:17:10")))
            }
        }

        @Test func aDoubleClickOnAMatchCopiesIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.doubleClick(onText: "11:17:10")

                #expect(app.copied == "2026-10-07 11:17:10")
                #expect(CopiedHUD.panel?.isVisible == true)
                #expect(app.selectedTabTitle == "datetime")
                // It fades in, holds fully shown, then fades out and goes.
                app.spin(0.3)
                #expect(CopiedHUD.panel?.alphaValue == 1)
                app.spin(1.2)
                #expect(CopiedHUD.panel?.isVisible == false)
            }
        }

        @Test func aClickOnJSONCopiesItRawOrBeautifiedPerCopyJSON() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.doubleClick(onText: #""method""#)
                #expect(app.copied == AppFixtures.jsonPayload)

                var config = Config.default
                config.copyJSON = .pretty
                try app.writeConfig(String(decoding: ConfigFile.encode(config), as: UTF8.self))
                app.doubleClick(onText: #""method""#)
                #expect(app.copied == JSONValue.parse(AppFixtures.jsonPayload)?.prettyPrinted)
            }
        }

        @Test func anUnknownCopyJSONWarnsAndCopiesRaw() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                { "copyJSON": "fancy", "patterns": [{ "name": "json", "builtin": "json", "actions": ["copy"] }] }
                """#)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.doubleClick(onText: #""method""#)
                #expect(app.copied == AppFixtures.jsonPayload)
                #expect(app.model.warnings.contains { $0.contains("copyJSON") })
            }
        }

        @Test func doubleClickingAURLNestedInTheJSONCopiesTheWholeJSON() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.doubleClick(onText: "app.bo.test")
                #expect(app.copied == AppFixtures.jsonPayload)
            }
        }

        @Test func aDragInsideAMatchSelectsWithoutCopying() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                let method = app.range(of: #""method":"where""#)
                app.drag(from: app.point(inInput: method), to: app.point(inInputEndOf: method))

                #expect(app.copied == nil)
                #expect(app.textView.selectedRange().length > 0)
                #expect(NSIntersectionRange(app.textView.selectedRange(), method).length > 0)
            }
        }

        @Test func aDoubleClickOnPlainTextSelectsAWord() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.doubleClick(onText: "invoked")

                #expect(app.textView.selectedRange() == app.range(of: "invoked"))
                #expect(app.selectedTabTitle == "json")
            }
        }

        @Test func thePointingHandShowsOverMatchesOnlyWhileHighlighting() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                @MainActor func handOver(_ text: String) -> Bool {
                    let point = app.textView.convert(app.point(inInput: app.range(of: text)), from: nil)
                    return app.textView.pointingHandRects.contains { $0.contains(point) }
                }

                // Cursor rects, like a link's, so the window shows the hand over a pill
                // itself and never flashes the I-beam on the way.
                #expect(handOver("11:17:10"))
                #expect(!handOver("invoked"))

                app.shortcut("e")
                #expect(!handOver("11:17:10"))
            }
        }

        @Test func highlightingOffRemovesTintsAndClicksButTheInspectorKeepsUpdating() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.shortcut("e"))
                #expect(!app.model.highlighting)
                #expect(app.tint(at: "2026-10-07").background == nil)
                app.click(onText: "11:17:10")
                #expect(app.selectedTabTitle == "json")
                app.doubleClick(onText: "11:17:10")
                #expect(app.copied == nil)
                #expect(app.selectedTabTitle == "json")

                app.type(" 1759835830", at: (app.textView.string as NSString).length)
                #expect(app.inspection.tabs.first { $0.title == "datetime" }?.entries.count == 2)
                #expect(app.tint(at: "1759835830").background == nil)

                app.shortcut("e")
                #expect(app.model.highlighting)
                #expect(app.tint(at: "2026-10-07").background != nil)
            }
        }

        @Test func matchesArePillsInTheirTintWithColoredTextAndNoUnderline() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                let datetime = try #require(app.textView.pills.first { $0.range == app.range(of: "2026-10-07 11:17:10") })
                #expect(!datetime.isStrong && !datetime.hasRing)
                let attributes = app.textView.layoutManager!.temporaryAttributes(
                    atCharacterIndex: datetime.range.location, effectiveRange: nil
                )
                #expect(attributes[.underlineStyle] == nil)
                #expect(hex(attributes[.foregroundColor] as? NSColor, in: .aqua) == datetime.color.roles(in: .light).text)
            }
        }

        @Test func theInspectorsSelectionIsRingedInTheInputANestedOneInsideItsParent() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                let json = try #require(app.model.selectedEntry)
                #expect(app.textView.pills.filter(\.hasRing).map(\.range) == [json.range])

                try app.select("file path", 3)
                let path = try #require(app.model.selectedEntry)
                let ringed = try #require(app.textView.pills.last)
                #expect(ringed.hasRing && ringed.isStrong)
                #expect(ringed.range == path.range)
                #expect(ringed.color == app.inspection.tabs.first { $0.title == "file path" }?.color)
                #expect(app.textView.pills.contains { $0.range == json.range && !$0.hasRing })

                try app.select("Plain Text", 0)
                #expect(app.textView.pills.allSatisfy { !$0.hasRing })
            }
        }

        @Test func aMatchThatWrapsIsOneShapeAcrossItsLines() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let layoutManager = try #require(app.textView.layoutManager as? PillLayoutManager)
                let json = app.range(of: AppFixtures.jsonPayload)

                let pieces = layoutManager.pieces(of: json)
                #expect(pieces.count > 3)
                let shapes = layoutManager.shapes(of: json)
                #expect(shapes.count == 1)
                // It covers the gap between its lines, where their pieces overlap.
                let first = pieces[1], second = pieces[2]
                let gap = NSPoint(x: max(first.minX, second.minX) + 20, y: (first.maxY + second.minY) / 2)
                #expect(shapes[0].contains(gap))
                // And nothing right of a line's piece.
                #expect(!shapes[0].contains(NSPoint(x: first.maxX + 4, y: first.midY)))
            }
        }

        @Test func aRedrawOfSomeLinesOutlinesThemAsTheWholePillDoes() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                // A pretty-printed JSON: one pill over lines of ragged widths.
                let json = "{\n" + (0..<40).map {
                    #"  "key\#($0)": "\#(String(repeating: "v", count: [4, 30, 12, 50][$0 % 4]))""#
                }.joined(separator: ",\n") + "\n}"
                app.capture(json)
                let layoutManager = try #require(app.textView.layoutManager as? PillLayoutManager)
                let range = app.range(of: json)
                let whole = layoutManager.shapes(of: range)
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var starts = [0]
                for (offset, unit) in json.utf16.enumerated() where unit == 10 { starts.append(offset + 1) }

                // Windows of lines: the top, the middle, the bottom, and one starting
                // and ending mid-line.
                let windows = [
                    NSRange(location: 0, length: starts[3]),
                    NSRange(location: starts[18], length: starts[22] - starts[18]),
                    NSRange(location: starts[38], length: NSMaxRange(glyphs) - starts[38]),
                    NSRange(location: starts[9] + 5, length: starts[12] + 3 - starts[9] - 5),
                ]
                for window in windows {
                    let partial = layoutManager.shapes(of: range, around: window)
                    var line = NSRange(location: window.location, length: 0)
                    while line.location < NSMaxRange(window) {
                        let rect = layoutManager.lineFragmentRect(forGlyphAt: line.location, effectiveRange: &line)
                        for y in [rect.minY + 1, rect.midY, rect.maxY - 1] {
                            for x in stride(from: rect.minX, through: rect.minX + 500, by: 3) {
                                let point = NSPoint(x: x, y: y)
                                #expect(
                                    whole.contains { $0.contains(point) } == partial.contains { $0.contains(point) },
                                    "\(point) in window \(window)"
                                )
                            }
                        }
                        line.location = NSMaxRange(line)
                    }
                }
            }
        }

        @Test func linePiecesThatDontOverlapAcrossTheBreakAreSeparateShapes() {
            // "…{" at a line's end, then "…}" at the next one's start: joined they'd
            // pinch to a sliver, so they stay apart.
            let pieces = [NSRect(x: 500, y: 0, width: 40, height: 20), NSRect(x: 0, y: 24, width: 200, height: 20)]
            #expect(PillLayoutManager.shapes(joining: pieces).count == 2)

            let overlapping = [NSRect(x: 100, y: 0, width: 400, height: 20), NSRect(x: 0, y: 24, width: 300, height: 20)]
            let joined = PillLayoutManager.shapes(joining: overlapping)
            #expect(joined.count == 1)
            #expect(joined[0].contains(NSPoint(x: 200, y: 22)))
            #expect(!joined[0].contains(NSPoint(x: 50, y: 10)))
            #expect(!joined[0].contains(NSPoint(x: 400, y: 34)))
        }

        @Test func aTallPillIsOneOutlineWithoutPointsAlongItsStraightEdges() {
            // A pretty-printed JSON's lines: one left edge, ragged right edges.
            let pieces = (0..<5000).map {
                NSRect(x: 0, y: CGFloat($0) * 24, width: $0.isMultiple(of: 3) ? 300 : 200, height: 20)
            }
            let shapes = PillLayoutManager.shapes(joining: pieces)
            #expect(shapes.count == 1)
            #expect(shapes[0].contains(NSPoint(x: 10, y: 24 * 2500 + 10)))
            #expect(!shapes[0].contains(NSPoint(x: 250, y: 24 * 1 + 10)))
            #expect(shapes[0].contains(NSPoint(x: 250, y: 24 * 3 + 10)))

            // A plain block: its four corners and nothing between them.
            let block = PillLayoutManager.shapes(joining: (0..<1000).map {
                NSRect(x: 0, y: CGFloat($0) * 24, width: 300, height: 20)
            })
            #expect(block.count == 1)
            #expect(block[0].elementCount < 20)
        }

        @Test func pillsMoveWithTheirTextWhileTypingAndAnEditedMatchLosesItsPill() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let layoutManager = try #require(app.textView.layoutManager)
                @MainActor func pillTexts() -> [String] {
                    let text = app.textView.string as NSString
                    return app.textView.pills.map { text.substring(with: $0.range) }
                }
                @MainActor func color(at location: Int) -> Any? {
                    layoutManager.temporaryAttributes(atCharacterIndex: location, effectiveRange: nil)[.foregroundColor]
                }
                // The datetime, and the JSON, selected, with its ring.
                #expect(pillTexts() == ["2026-10-07 11:17:10", AppFixtures.jsonPayload])

                // Typing before them moves their pills along with their text at once,
                // before the re-inspection; the pointer finds them where they went.
                app.textView.setSelectedRange(NSRange(location: 0, length: 0))
                app.textView.insertText("ab ", replacementRange: NSRange(location: 0, length: 0))
                #expect(pillTexts() == ["2026-10-07 11:17:10", AppFixtures.jsonPayload])
                let datetime = app.range(of: "2026-10-07 11:17:10")
                app.textView.mouseMoved(with: app.mouseEvent(.mouseMoved, at: app.point(inInput: datetime)))
                #expect(app.textView.pills.first { $0.range == datetime }?.isStrong == true)
                #expect(color(at: datetime.location) != nil)
                #expect(color(at: 0) == nil)

                // Typing inside one takes its pill and its text color away.
                app.textView.setSelectedRange(NSRange(location: datetime.location + 4, length: 0))
                app.textView.insertText("9", replacementRange: NSRange(location: datetime.location + 4, length: 0))
                #expect(pillTexts() == [AppFixtures.jsonPayload])
                #expect(color(at: datetime.location) == nil)
                #expect(color(at: app.range(of: AppFixtures.jsonPayload).location) != nil)

                // So does deleting across one, the selected one's ring too.
                let url = app.range(of: #""url""#)
                app.textView.setSelectedRange(NSRange(location: url.location - 1, length: url.length + 1))
                app.textView.deleteBackward(nil)
                #expect(app.textView.pills.isEmpty)
                #expect(color(at: url.location) == nil)

                // The re-inspection brings back what's still a Match.
                app.waitForInspection()
                #expect(!app.textView.pills.isEmpty)
            }
        }

        @Test func aPillThatAppearsWhileTypingFadesInAndOthersDont() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let layoutManager = try #require(app.textView.layoutManager as? PillLayoutManager)
                // A capture shows its pills at once.
                #expect(layoutManager.fadingRanges.isEmpty)

                // Typing before every Match moves them all, but only the new one fades in.
                app.textView.setSelectedRange(NSRange(location: 0, length: 0))
                app.textView.insertText("https://x.test ", replacementRange: NSRange(location: 0, length: 0))
                // Just past the re-inspection's debounce, mid-fade.
                app.spin(0.2)
                guard !Motion.isReduced else { return }
                let url = app.range(of: "https://x.test")
                #expect(layoutManager.fadingRanges == [url])

                app.spin(0.3)
                #expect(layoutManager.fadingRanges.isEmpty)
            }
        }

        @Test func anEditDropsABackgroundInspectionOfTheTextBeforeIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let urls = ["https://a.test/1", "https://a.test/2"]
                app.controller.show(input: "\(urls[0]) " + largeFiller + " \(urls[1])")
                app.waitForBackgroundInspection()
                #expect(app.textView.pills.count == 2)

                // A config reload's inspection finishes in the background, its result not
                // yet taken: the main run loop hasn't turned.
                app.controller.configDidChange()
                PanelModel.inspections.sync {}
                // Typing between the URLs meanwhile moves the second one's pill.
                let middle = NSRange(location: urls[0].count + 10, length: 0)
                app.textView.setSelectedRange(middle)
                app.textView.insertText("typed ", replacementRange: middle)
                // The result's turn comes, well before the typing pause ends.
                app.spin(0.05)

                // It described the text before the edit, so it's dropped: both pills stay
                // where the edit moved them.
                #expect(app.model.isInspecting)
                let pills = app.textView.pills.map(\.range).sorted { $0.location < $1.location }
                #expect(pills == urls.map(app.range(of:)))

                // Then the edit's own inspection lands.
                app.waitForInspection()
                app.waitForBackgroundInspection()
                #expect(!app.model.isInspecting)
                #expect(app.inspection.matches.map(\.range) == urls.map(app.range(of:)))
            }
        }

        @Test func typingDuringABackgroundInspectionDropsItsResultForTheNewerOnes() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                // Making the window sets the model's callback, so make it before wrapping that.
                _ = app.panel
                var shown: [Inspection] = []
                let inspectionDidChange = app.model.onInspectionChange
                app.model.onInspectionChange = { inspection in
                    shown.append(inspection)
                    inspectionDidChange(inspection)
                }
                let first = "https://a.test/1"
                app.controller.show(input: "\(first) " + largeFiller)
                // The capture's inspection finishes in the background, its result not yet
                // taken: the main run loop hasn't turned.
                PanelModel.inspections.sync {}
                #expect(app.model.isInspecting)

                // Typing meanwhile; its inspection starts, as the debounce would start it.
                let second = "https://a.test/2"
                let end = (app.textView.string as NSString).length
                app.textView.insertText(" \(second)", replacementRange: NSRange(location: end, length: 0))
                app.model.inspect(app.textView.string, fresh: false)

                app.waitForBackgroundInspection()
                app.waitForInspection()
                app.waitForBackgroundInspection()
                // Only the capture's emptied Inspection, then those of the typed text.
                #expect(shown.first?.matches.isEmpty == true)
                #expect(shown.count >= 2)
                #expect(shown.dropFirst().allSatisfy { $0.matches.map(\.text) == [first, second] })
                #expect(app.inspection.matches.map(\.text) == [first, second])
                #expect(app.textView.pills.count == 2)
            }
        }

        @Test func aLogLevelsPillAndRowTakeItsColorRulesColor() async throws {
            try await runInApp {
                var config = Config.default
                let index = try #require(config.patterns.firstIndex { $0.name == "log level" })
                config.patterns[index].enabled = true
                let app = try AppHarness(config: String(decoding: ConfigFile.encode(config), as: UTF8.self))
                defer { app.tearDown() }
                app.capture("develop.WARNING: slow; develop.ERROR: failed")

                let warning = try #require(app.textView.pills.first { $0.range == app.range(of: "WARNING") })
                let error = try #require(app.textView.pills.first { $0.range == app.range(of: "ERROR") })
                #expect(warning.color == PatternColor("#ffe629"))
                #expect(error.color == PatternColor("#e5484d"))
                let entries = try #require(app.inspection.tab(.pattern("log level"))).entries
                #expect(entries.map(\.color) == [warning.color, error.color])

                try app.select("log level", 0)
                #expect(app.textView.pills.last?.hasRing == true)
                #expect(app.textView.pills.last?.color == warning.color)
            }
        }

        @Test func hoveringAPillDeepensIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let datetime = app.range(of: "2026-10-07 11:17:10")

                app.textView.mouseMoved(with: app.mouseEvent(.mouseMoved, at: app.point(inInput: datetime)))
                #expect(app.textView.pills.first { $0.range == datetime }?.isStrong == true)

                app.textView.mouseMoved(with: app.mouseEvent(.mouseMoved, at: app.point(inInput: app.range(of: "invoked"))))
                #expect(app.textView.pills.first { $0.range == datetime }?.isStrong == false)
            }
        }

        @Test func textScrolledSidewaysDoesntShowUnderTheLineNumbers() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(Array(repeating: "[2026-10-07 11:17:10] " + String(repeating: "word ", count: 80), count: 4)
                    .joined(separator: "\n"))
                app.model.wrapsLines = false
                app.spin(0.2)
                let scrollView = try #require(app.textView.enclosingScrollView)
                let ruler = try #require(scrollView.verticalRulerView as? LineNumberRuler)
                let clipView = scrollView.contentView
                // Where the gutter ends, in the clip view, which starts under it.
                let edge = ruler.frame.maxX - clipView.frame.minX
                @MainActor func opacity(atX x: CGFloat) throws -> CGFloat {
                    let mask = try #require(clipView.layer?.mask as? CAGradientLayer)
                    let stops = try #require(mask.locations).map { CGFloat($0.doubleValue) * clipView.frame.width }
                    // The mask is clear, clear, black, black at its stops.
                    if x <= stops[1] { return 0 }
                    if x >= stops[2] { return 1 }
                    return (x - stops[1]) / (stops[2] - stops[1])
                }

                // Not scrolled: the text starts past the gutter, sharp.
                #expect(try opacity(atX: edge - 1) == 0)
                #expect(try opacity(atX: edge + 1) == 1)

                // Scrolled sideways: hidden under the gutter, fading in past it.
                clipView.scroll(to: NSPoint(x: 120, y: clipView.bounds.minY))
                scrollView.reflectScrolledClipView(clipView)
                #expect(try opacity(atX: edge - 1) == 0)
                #expect(try opacity(atX: edge + LineNumberRuler.gutterFade / 2) > 0)
                #expect(try opacity(atX: edge + LineNumberRuler.gutterFade / 2) < 1)
                #expect(try opacity(atX: edge + LineNumberRuler.gutterFade + 1) == 1)
            }
        }

        @Test func theGutterNumbersLinesAndAWrappedLineCountsOnce() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let long = String(repeating: "word ", count: 400)
                app.capture("first\n\(long)\nthird")

                let scrollView = try #require(app.textView.enclosingScrollView)
                let ruler = try #require(scrollView.verticalRulerView as? LineNumberRuler)
                #expect(scrollView.rulersVisible)
                #expect(ruler.lineStarts.count == 3)
                #expect(ruler.lineNumber(at: 0) == 1)
                #expect(ruler.lineNumber(at: app.range(of: "word").location + 1000) == 2)
                #expect(ruler.lineNumber(at: app.range(of: "third").location) == 3)

                app.type("\nfourth", at: (app.textView.string as NSString).length)
                #expect(ruler.lineStarts.count == 4)

                // The cursor's line stands out, and follows it.
                app.textView.setSelectedRange(NSRange(location: app.range(of: "third").location, length: 0))
                #expect(ruler.currentLine == 3)
                app.textView.setSelectedRange(NSRange(location: 0, length: 0))
                #expect(ruler.currentLine == 1)
            }
        }

        @Test func everyLineBreakTheTextSystemBreaksAtStartsANumberedLine() {
            // CR, U+2028, CRLF (once), U+2029, NEL.
            #expect(LineNumberRuler.lineStarts(in: "a\rb\u{2028}c\r\nd\u{2029}e\u{85}f") == [0, 2, 4, 7, 9, 11])
        }

        @Test func aPillAcrossCarriageReturnLinesEndsWithEachLinesText() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture("{\"a\": 1,\r\"b\": 2,\r\"c\": 3}")
                let layoutManager = try #require(app.textView.layoutManager as? PillLayoutManager)

                let json = try #require(app.textView.pills.first)
                let lines = layoutManager.pieces(of: json.range)
                #expect(lines.count == 3)
                // Not out to the Input's right edge, as the line break's glyph would take it.
                #expect(lines.allSatisfy { $0.width < 120 })
                let ruler = try #require(app.textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler)
                #expect(ruler.lineStarts.count == 3)
            }
        }

        @Test func wrapLinesTogglesBetweenWrappingAndScrollingSidewaysAndIsRemembered() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer {
                    app.model.wrapsLines = true
                    app.tearDown()
                }
                app.capture(String(repeating: "word ", count: 400))
                let scrollView = try #require(app.textView.enclosingScrollView)
                #expect(app.textView.textContainer?.widthTracksTextView == true)
                #expect(app.textView.frame.width <= scrollView.contentSize.width + 1)

                app.model.wrapsLines = false
                app.spin()
                #expect(app.textView.textContainer?.widthTracksTextView == false)
                #expect(app.textView.frame.width > scrollView.contentSize.width * 2)
                #expect(UserDefaults.standard.bool(forKey: PanelModel.wrapsLinesKey) == false)

                app.model.wrapsLines = true
                app.spin()
                #expect(app.textView.frame.width <= scrollView.contentSize.width + 1)
            }
        }

        /// A trackpad scroll reads the scroll view's `documentView` off the main
        /// thread (AppKit's concurrent scrolling), so the Input's scroll view must
        /// not make that main-actor-isolated by overriding it: that trapped.
        @Test func theInputsScrollViewCanBeReadOffTheMainThreadAsScrollingDoes() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture("x")
                nonisolated(unsafe) let scrollView = try #require(app.textView.enclosingScrollView)

                // On a background thread (`sync` would run it on this one) and through
                // Objective-C, as AppKit calls it.
                nonisolated(unsafe) var read = false
                let done = DispatchGroup()
                done.enter()
                Thread.detachNewThread {
                    read = scrollView.perform(#selector(getter: NSScrollView.documentView)) != nil
                    done.leave()
                }
                done.wait()
                #expect(read)
            }
        }

        @Test func theInputFadesOnlyAtEdgesWithTextScrolledPastThem() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture("one line")
                let scrollView = try #require(app.textView.enclosingScrollView as? FadingScrollView)
                #expect(scrollView.fadingEdges == (false, false))

                app.capture((1...200).map { "line \($0)" }.joined(separator: "\n"))
                app.spin()
                #expect(scrollView.fadingEdges == (false, true))

                app.textView.scrollToEndOfDocument(nil)
                app.spin()
                #expect(scrollView.fadingEdges == (true, false))
            }
        }

        @Test func aNewCaptureTurnsHighlightingBackOn() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                app.shortcut("e")
                #expect(!app.model.highlighting)

                app.capture(AppFixtures.monologLine)
                #expect(app.model.highlighting)
            }
        }
    }
}
