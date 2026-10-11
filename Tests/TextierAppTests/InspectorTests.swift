import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor
    @Suite("The Action bar and Match Windows")
    struct ActionBarTests {
        @Test func aURLOffersOpenInBrowserFirstThenCopyAndPopOut() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("url", 0)

                #expect(app.actionBar == ["Open in Browser", "Copy", "Pop Out"])
                try app.runAction("Open in Browser")
                #expect(app.openedURLs == [URL(string: "http://app.bo.test/player/api/v1/signin")!])
            }
        }

        @Test func aFilePathOffersOpenInEditorFirst() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("file path", 1)

                #expect(app.actionBar.first == "Open in Editor")
                app.model.runFirstAction()
                #expect(app.openedFiles == [FileLocation(path: AppFixtures.backtraceFile, line: 80)])
            }
        }

        @Test func aPairedFilePathOffersCopyWithLineAndCopyKeepsTheLoggedPath() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("file path", 3)

                #expect(app.actionBar == ["Open in Editor", "Copy", "Copy with Line", "Pop Out"])
                try app.runAction("Copy with Line")
                #expect(app.copied == AppFixtures.dispatcherFile + ":603")
                try app.runAction("Copy")
                #expect(app.copied == AppFixtures.dispatcherFile)
                try app.runAction("Open in Editor")
                #expect(app.openedFiles == [FileLocation(path: AppFixtures.dispatcherFile, line: 603)])
            }
        }

        @Test func anUnpairedFilePathHasNoCopyWithLine() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine + " at /tmp/app.log:12")
                try app.select("file path", 0)
                #expect(app.actionBar == ["Open in Editor", "Copy", "Pop Out"])
                app.model.runFirstAction()
                try app.select("file path", 6)
                #expect(app.actionBar == ["Open in Editor", "Copy", "Pop Out"])
                app.model.runFirstAction()
                #expect(app.openedFiles == [
                    FileLocation(path: AppFixtures.callerFile, line: nil), FileLocation(path: "/tmp/app.log", line: 12),
                ])
            }
        }

        @Test func aPoppedOutPairedFilePathKeepsItsLineAndCopyWithLine() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("file path", 1)
                try app.runAction("Pop Out")

                let window = try #require(app.matchWindows.last)
                #expect(window.model.barItems.map(\.title) == ["Open in Editor", "Copy", "Copy with Line"])
                window.model.run(.copyWithLine)
                #expect(app.copied == AppFixtures.backtraceFile + ":80")
                window.model.run(.action(.openFile))
                #expect(app.openedFiles == [FileLocation(path: AppFixtures.backtraceFile, line: 80)])
            }
        }

        @Test func jsonOffersPopOutFirstAndOnlyOnce() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.actionBar == ["Pop Out", "Copy Beautified", "Copy"])
                try app.runAction("Copy Beautified")
                #expect(app.copied == JSONValue.parse(AppFixtures.jsonPayload)?.prettyPrinted)
                try app.runAction("Copy")
                #expect(app.copied == AppFixtures.jsonPayload)
            }
        }

        @Test func jsonKeepsCopyBeautifiedEvenWhenItsActionsLeaveItOut() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                { "patterns": [{ "name": "json", "builtin": "json", "actions": ["open"] }] }
                """#)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.actionBar == ["Pop Out", "Copy Beautified", "Copy"])
            }
        }

        @Test func jsonWithoutOpenOffersPopOutInstead() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                { "patterns": [{ "name": "json", "builtin": "json", "actions": ["copy"] }] }
                """#)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.actionBar == ["Copy", "Copy Beautified", "Pop Out"])
            }
        }

        @Test func plainTextOffersOnlyCopy() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("Plain Text", 0)

                #expect(app.actionBar == ["Copy"])
                app.shortcut("p", [.command, .shift])
                #expect(app.matchWindows.isEmpty)
            }
        }

        @Test func popOutShowsTheEntrysActionBarAndJSONViewer() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                try app.runAction("Pop Out")

                let window = try #require(app.matchWindows.last)
                #expect(window.window.isVisible)
                #expect(window.window.title == "textier — json")
                #expect(window.model.entry.text == AppFixtures.jsonPayload)
                // Already in a window: nothing offers to open it again.
                #expect(window.model.barItems.map(\.title) == ["Copy Beautified", "Copy"])
                app.spin(0.2)
                #expect(app.outlineView(in: window.window)?.node(keyPath: "backtrace[0].file") != nil)
            }
        }

        @Test func aMatchWindowHidesItsTitleAndCarriesItsPatternsGlyphColorAndActions() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("url", 0)
                app.shortcut("p", [.command, .shift])

                let controller = try #require(app.matchWindows.last)
                #expect(controller.window.title == "textier — url")
                #expect(controller.window.titleVisibility == .hidden)
                #expect(controller.window.titlebarAppearsTransparent)
                #expect(controller.window.standardWindowButton(.closeButton) != nil)
                #expect(controller.model.glyph == .url)
                #expect(controller.model.color == app.inspection.tab(.pattern("url"))?.color)
                #expect(!controller.model.barItems.contains(.popOut))
                #expect(controller.model.barItems.map(\.title) == ["Open in Browser", "Copy"])

                // The Action bar sits in the title bar's row: a click there reaches it,
                // not the title bar.
                let window = controller.window
                let frame = try #require(window.contentView?.superview)
                let titlebarHeight = window.frame.height - window.contentLayoutRect.height
                let actions = NSPoint(x: frame.bounds.maxX - 40, y: frame.bounds.maxY - titlebarHeight / 2)
                let hit = try #require(frame.hitTest(actions))
                #expect(hit.isDescendant(of: try #require(window.contentView)))
                let close = try #require(window.standardWindowButton(.closeButton))
                let lights = close.convert(NSPoint(x: close.bounds.midX, y: close.bounds.midY), to: frame)
                #expect(frame.hitTest(lights).map { !$0.isDescendant(of: window.contentView!) } == true)
            }
        }

        @Test func aMatchWindowsRawTextCanBeEditedWithoutTouchingTheInput() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.runAction("Pop Out")
                let model = try #require(app.matchWindows.last).model
                // Raw opens on the JSON beautified, which isn't an edit: Copy still
                // copies the Match as it is.
                #expect(model.rawText == JSONValue.parse(AppFixtures.jsonPayload)?.prettyPrinted)
                #expect(!model.isEdited && !model.showsOriginal && !model.canBeautify)
                model.run(.action(.copy))
                #expect(app.copied == AppFixtures.jsonPayload)

                // An edit is parsed again: the JSON Viewer, preview and Actions follow it.
                model.rawText = #"{"url": "http://edited.test/x", "n": 2}"#
                app.spin(0.4)
                #expect(model.entry.text == model.rawText)
                guard case .json(let value) = model.entry.detail else {
                    Issue.record("not parsed as JSON")
                    return
                }
                #expect(value["n"] == .number("2"))
                #expect(model.isEdited && model.problem == nil)
                #expect(model.title == "json 0")
                model.run(.action(.copy))
                #expect(app.copied == model.rawText)
                // The Input keeps what was captured.
                #expect(app.textView.string == AppFixtures.monologLine)
                #expect(app.model.selectedEntry?.text == AppFixtures.jsonPayload)

                // Text that isn't JSON any more says where it stops, and shows as text.
                model.rawText = "{\n\"url\": "
                app.spin(0.4)
                #expect(model.problem == "Not valid JSON from line 2. Shown as text.")
                if case .json = model.entry.detail { Issue.record("still JSON") }

                // View Original: the text as it is in the Input, which Beautify lays out again.
                model.viewOriginal()
                #expect(model.rawText == AppFixtures.jsonPayload)
                #expect(model.entry.text == AppFixtures.jsonPayload)
                #expect(!model.isEdited && model.problem == nil)
                #expect(model.showsOriginal && model.canBeautify)
            }
        }

        @Test func rawJSONIsColoredLikeTextModeAndFollowsEdits() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.runAction("Pop Out")
                let controller = try #require(app.matchWindows.last)
                controller.model.mode = .raw
                app.spin(0.2)
                func editor(in view: NSView) -> NSTextView? {
                    if let text = view as? NSTextView, text.isEditable { return text }
                    return view.subviews.lazy.compactMap(editor(in:)).first
                }
                let content = try #require(controller.window.contentView)
                let textView = try #require(editor(in: content))
                func color(at text: String) -> String? {
                    let location = (textView.string as NSString).range(of: text).location
                    let color = textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
                    var hex: String?
                    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { hex = color?.hexString }
                    return hex
                }
                let dark = Theme.githubDark
                #expect(color(at: #""method""#) == dark.style(for: .key).color)
                #expect(color(at: #""where""#) == dark.style(for: .string).color)

                // Typing recolors: a new number takes the number color.
                textView.setSelectedRange(NSRange(location: 1, length: 0))
                textView.insertText(#""n": 42, "#, replacementRange: NSRange(location: 1, length: 0))
                #expect(color(at: "42") == dark.style(for: .number).color)
                #expect(color(at: #""n""#) == dark.style(for: .key).color)
            }
        }

        @Test func beautifyLaysOutARawJSONOverLines() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.runAction("Pop Out")
                let model = try #require(app.matchWindows.last).model
                model.viewOriginal()
                #expect(model.canBeautify)

                model.beautify()
                #expect(model.rawText == JSONValue.parse(AppFixtures.jsonPayload)?.prettyPrinted)
                // Already beautified: nothing more to do.
                #expect(!model.canBeautify)
                app.spin(0.4)
                #expect(model.problem == nil)
                if case .json = model.entry.detail {} else { Issue.record("not parsed as JSON") }
            }
        }

        @Test func aPlainTextMatchWindowOpensStraightIntoItsEditableText() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                { "patterns": [{ "name": "php class", "regex": "\\b[A-Z]\\w+Repository\\b", "actions": ["copy"] }] }
                """#)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("php class", 0)
                try app.runAction("Pop Out")
                let model = try #require(app.matchWindows.last).model

                // Nothing to parse: no Parsed | Raw, just the text to edit.
                #expect(!model.hasParsedView)
                #expect(model.mode == .raw)
                #expect(model.rawText == "EmailTemplateRepository")
            }
        }

        @Test func aURLsRawTextEditedIntoSomethingElseSaysSo() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("url", 0)
                try app.runAction("Pop Out")
                let model = try #require(app.matchWindows.last).model
                #expect(!model.canBeautify)
                #expect(model.hasParsedView && model.mode == .parsed)

                model.rawText = "https://other.test/path?q=1"
                app.spin(0.4)
                guard case .url(let url) = model.entry.detail else {
                    Issue.record("not parsed as a URL")
                    return
                }
                #expect(url.host == "other.test")

                model.rawText = "not a link"
                app.spin(0.4)
                #expect(model.problem == "Not a url Match any more. Shown as text.")
            }
        }

        @Test func popOutOpensManyMatchWindowsThatFollowConfigReloads() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.shortcut("p", [.command, .shift])
                try app.select("url", 0)
                app.shortcut("p", [.command, .shift])
                #expect(app.matchWindows.count == 2)
                #expect(app.matchWindows.map(\.model.patternName) == ["json", "url"])
                #expect(app.matchWindows[1].model.barItems.map(\.title) == ["Open in Browser", "Copy"])

                var config = Config.default
                config.patterns[2].actions = [.copy]  // url
                try app.writeConfig(String(decoding: ConfigFile.encode(config), as: UTF8.self))
                #expect(app.matchWindows[1].model.entry.actions == [.copy])
            }
        }

        @Test func viewOriginalKeepsTheActionsOfTheLastReload() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("url", 0)
                try app.runAction("Pop Out")
                let model = try #require(app.matchWindows.last).model
                let original = model.rawText

                var config = Config.default
                config.patterns[2].actions = [.copy]  // url
                try app.writeConfig(config)
                model.rawText = "https://other.test/"
                app.spin(0.4)
                model.viewOriginal()
                #expect(model.entry.actions == [.copy])

                // Typing the original text back is View Original too.
                model.rawText = "https://other.test/"
                app.spin(0.4)
                model.rawText = original
                app.spin(0.4)
                #expect(!model.isEdited)
                #expect(model.entry.actions == [.copy])
            }
        }

        @Test func anEscapedJSONMatchWindowStaysJSONThroughBeautifyAndReloads() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let string = #"{"a":1,"b":[1,2]}"#
                let config = app.store.config
                let pattern = try #require(config.escapedJSONPattern)
                Action.open.perform(on: Match(
                    range: NSRange(string.startIndex..., in: string), text: string, patternName: pattern.name,
                    patternIndex: try #require(config.patterns.firstIndex(of: pattern)), actions: pattern.actions
                ))
                app.spin(0.2)
                let window = try #require(app.matchWindows.last)
                let model = window.model

                // Raw opens on it beautified.
                #expect(model.rawText == JSONValue.parse(string)?.prettyPrinted)
                #expect(model.problem == nil)
                if case .json = model.entry.detail {} else { Issue.record("not parsed as JSON") }
                #expect(app.outlineView(in: window.window)?.node(keyPath: "b[1]") != nil)

                // A reload gives it the escaped-json Pattern's Actions.
                var edited = Config.default
                let index = try #require(edited.patterns.firstIndex { $0.kind == .builtin(.escapedJSON) })
                edited.patterns[index].actions = [.copy, .open]
                try app.writeConfig(edited)
                #expect(model.entry.actions == [.copy, .open])

                // And keeps them through an edit, though its tree is the json Pattern's.
                model.rawText = #"{"a":2,"b":[1,2]}"#
                for _ in 0..<20 where model.entry.text != model.rawText { app.spin(0.05) }
                #expect(model.entry.text == model.rawText)
                #expect(model.entry.actions == [.copy, .open])
            }
        }

        @Test func beautifyInRawIsUndoneWithTheTypingBeforeIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.runAction("Pop Out")
                let controller = try #require(app.matchWindows.last)
                controller.model.mode = .raw
                app.spin(0.2)
                @MainActor func editor(in view: NSView) -> NSTextView? {
                    if let text = view as? NSTextView, text.isEditable { return text }
                    return view.subviews.lazy.compactMap(editor(in:)).first
                }
                let content = try #require(controller.window.contentView)
                let textView = try #require(editor(in: content))

                textView.setSelectedRange(NSRange(location: 1, length: 0))
                textView.insertText(#""n": 42, "#, replacementRange: NSRange(location: 1, length: 0))
                app.spin(0.4)
                controller.model.beautify()
                app.spin(0.1)
                #expect(textView.string == controller.model.rawText)

                // Beautify was an undo step of its own, so the typing's undo still
                // lands on the text it was typed into (a test's steps share one group).
                let undoManager = try #require(textView.undoManager)
                for _ in 0..<3 where undoManager.canUndo { undoManager.undo() }
                let opening = try #require(JSONValue.parse(AppFixtures.jsonPayload)?.prettyPrinted)
                #expect(textView.string == opening)
                app.spin(0.4)
                #expect(controller.model.rawText == opening)
                #expect(!controller.model.isEdited)
            }
        }

        @Test func aCopyInTheRawEditorIsTextiersOwn() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.runAction("Pop Out")
                let controller = try #require(app.matchWindows.last)
                controller.model.mode = .raw
                app.spin(0.2)
                @MainActor func editor(in view: NSView) -> NSTextView? {
                    if let text = view as? NSTextView, text.isEditable { return text }
                    return view.subviews.lazy.compactMap(editor(in:)).first
                }
                let textView = try #require(controller.window.contentView.flatMap(editor(in:)))
                // TextKit 1 with its line numbers, as before.
                #expect(textView.textLayoutManager == nil)
                #expect(textView.enclosingScrollView?.verticalRulerView is LineNumberRuler)

                textView.setSelectedRange(NSRange(location: 0, length: 6))
                textView.copy(nil)
                #expect(app.copied == String(textView.string.prefix(6)))
                #expect(lastOwnCopy == app.pasteboard.changeCount)
            }
        }

        /// The editor command failed: the file opens with its default app only when
        /// that app just shows it.
        @Test func openInEditorsFallbackShowsAScriptInFinder() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let script = app.folder.appendingPathComponent("run.command")
                let json = app.folder.appendingPathComponent("data.json")
                try Data("echo hi\n".utf8).write(to: script)
                try Data("{}".utf8).write(to: json)

                #expect(Editor.openWithoutEditor(script.path) == "showed it in Finder")
                #expect(Editor.openWithoutEditor(json.path) == "opened it with the default app")
                #expect(Editor.openWithoutEditor(app.folder.path) == "showed it in Finder")
                // Nothing to show: Finder isn't sent looking for it.
                #expect(Editor.openWithoutEditor(app.folder.appendingPathComponent("missing.json").path) == "the file doesn't exist")
                #expect(app.openedWithDefaultApp.map(\.lastPathComponent) == ["data.json"])
                #expect(app.revealedInFinder.map(\.lastPathComponent) == ["run.command", app.folder.lastPathComponent])
            }
        }

        /// Only types whose default app just shows them open; the type comes from
        /// the extension, as Finder reads it.
        @Test func openInEditorsFallbackOpensOnlyWhatItsDefaultAppShows() throws {
            // Text, source code, data, images, PDFs.
            let shown = ["txt", "json", "md", "swift", "js", "log", "yaml", "csv", "sql", "png", "jpg", "pdf"]
            // Run, installed, imported or opened in a browser; scripts.
            let acted = [
                "jnlp", "mobileconfig", "configprofile", "html", "xhtml", "ics", "vcf", "svg",
                "command", "sh", "py", "scpt", "applescript",
            ]
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("textier-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            for (ext, opens) in shown.map({ ($0, true) }) + acted.map({ ($0, false) }) {
                let file = folder.appendingPathComponent("file.\(ext)")
                try Data("x".utf8).write(to: file)
                #expect(Editor.opensWithDefaultApp(file) == opens, "a .\(ext) file")
            }
        }

        @Test func anEntrysTooltipAndAWholeTextPreviewAreCut() {
            let lines = (1...20).map { "line \($0)" }
            let entry = InspectorEntry(wholeText: lines.joined(separator: "\n"), actions: [.copy])
            #expect(entry.tooltip == lines.prefix(10).joined(separator: "\n") + "…")
            let wide = String(repeating: "x", count: 1_000)
            #expect(InspectorEntry(wholeText: wide, actions: []).tooltip == String(repeating: "x", count: 300) + "…")
            #expect(InspectorEntry(wholeText: "short", actions: []).tooltip == "short")

            // A Match Window's header shows the preview: on one line, cut.
            let oneLine = lines.joined(separator: " ")
            #expect(entry.preview == String(oneLine.prefix(InspectorEntry.previewLength - 1)) + "…")
        }
    }

    @MainActor
    @Suite("Patterns that share a name")
    struct SharedNameTests {
        static func config(floatFirst: Bool = true) -> String {
            let float = #"{ "name": "numeric", "regex": "\\b\\d+\\.\\d+\\b", "actions": ["copy"] }"#
            let integer = #"{ "name": "numeric", "regex": "\\b\\d+\\b", "actions": ["copy", "open"] }"#
            let numeric = floatFirst ? "\(float), \(integer)" : "\(integer), \(float)"
            return #"{ "patterns": [{ "name": "json", "builtin": "json", "actions": ["open", "copy"] }, \#(numeric)] }"#
        }

        @Test func theyShareOneTabInOneColor() async throws {
            try await runInApp {
                let app = try AppHarness(config: Self.config())
                defer { app.tearDown() }
                app.capture("pi is 3.14, the answer 42")

                #expect(app.tabTitles == ["numeric", "Plain Text"])
                let tab = try #require(app.inspection.tab(.pattern("numeric")))
                #expect(tab.entries.map(\.text) == ["3.14", "42"])
                #expect(Set(app.inspection.matches.map(\.color)).count == 1)
            }
        }

        @Test func aMatchWindowKeepsItsOwnPatternsActionsAcrossAReload() async throws {
            try await runInApp {
                let app = try AppHarness(config: Self.config())
                defer { app.tearDown() }
                app.capture("pi is 3.14, the answer 42")
                try app.select("numeric", 1)
                #expect(app.actionBar == ["Copy", "Pop Out"])
                try app.runAction("Pop Out")

                let window = try #require(app.matchWindows.last)
                #expect(window.model.entry.actions == [.copy, .open])
                try app.writeConfig(Self.config(floatFirst: false))
                #expect(window.model.entry.actions == [.copy, .open])
            }
        }
    }

    @MainActor
    @Suite("Fields")
    struct FieldRowTests {
        static let accessLine = #"203.0.113.7 - - [09/Oct/2026:10:15:32 +0700] "GET /api/v1/signin HTTP/1.1" 200 512"#

        static var config: String {
            let access = Pattern(
                name: "access", regex: #"(?<client>\d+\.\d+\.\d+\.\d+) - - \[[^\]]+\] "\w+ (?<path>/\S+)"#,
                actions: [.copy]
            )
            return String(decoding: ConfigFile.encode(Config(patterns: Config.default.patterns + [access])), as: UTF8.self)
        }

        @Test func theInspectorShowsFieldRowsThatCopyAndOpenTheirValue() async throws {
            try await runInApp {
                let app = try AppHarness(config: Self.config)
                defer { app.tearDown() }
                app.capture(Self.accessLine)
                try app.select("access", 0)

                let fields = try #require(app.model.selectedEntry?.fields)
                #expect(fields.map(\.field.label) == ["client", "path"])
                fields[0].copy()
                #expect(app.copied == "203.0.113.7")
                #expect(fields[0].linkActions.isEmpty)
                #expect(fields[1].linkActions == [.openFile])
                Action.openFile.perform(on: try #require(fields[1].link))
                #expect(app.openedFiles == [FileLocation(path: "/api/v1/signin", line: nil)])
            }
        }

        @Test func aMatchWindowShowsTheSameFieldRows() async throws {
            try await runInApp {
                let app = try AppHarness(config: Self.config)
                defer { app.tearDown() }
                app.capture(Self.accessLine)
                try app.select("access", 0)
                try app.runAction("Pop Out")

                let window = try #require(app.matchWindows.last)
                #expect(window.model.entry.fields.map(\.field.value) == ["203.0.113.7", "/api/v1/signin"])
            }
        }

        @Test func theMatchsTextUnderItsFieldsIsSizedToItAndCopiesAsTextiersOwn() async throws {
            try await runInApp {
                let app = try AppHarness(config: Self.config)
                defer { app.tearDown() }
                app.capture(Self.accessLine)
                try app.select("access", 0)
                app.spin(0.2)
                let text = try #require(app.model.selectedEntry?.text)
                @MainActor func card(in view: NSView) -> NSTextView? {
                    if let textView = view as? OwnCopyTextView, !textView.isEditable, textView.string == text { return textView }
                    return view.subviews.lazy.compactMap(card(in:)).first
                }
                let textView = try #require(app.panel.contentView.flatMap(card(in:)))
                // A few lines, wrapped at the card's width; not the card's height.
                let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
                let lineHeight = try #require(textView.layoutManager?.defaultLineHeight(for: font))
                #expect(textView.frame.height >= lineHeight)
                #expect(textView.frame.height <= lineHeight * 8)

                textView.setSelectedRange(NSRange(location: 0, length: 11))
                textView.copy(nil)
                #expect(app.copied == "203.0.113.7")
                #expect(lastOwnCopy == app.pasteboard.changeCount)
            }
        }
    }

    @MainActor
    @Suite("Keyboard")
    struct KeyboardTests {
        @Test func commandDigitsSwitchTabsAndMissingOnesPassThrough() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.shortcut("1"))
                #expect(app.selectedTabTitle == "datetime")
                #expect(app.shortcut("4"))
                #expect(app.selectedTabTitle == "file path")
                #expect(!app.shortcut("9"))
                #expect(app.selectedTabTitle == "file path")
            }
        }

        @Test func draggingATabKeepsItsPlaceForLaterCaptures() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                #expect(app.tabTitles == ["datetime", "json", "url", "file path", "Plain Text"])

                app.model.moveTab(named: "file path", to: 0)
                #expect(app.tabTitles == ["file path", "datetime", "json", "url", "Plain Text"])
                #expect(UserDefaults.standard.stringArray(forKey: PanelModel.tabOrderKey) == ["file path", "datetime", "json", "url"])

                // A fresh capture, even one without some of them, keeps the arrangement.
                app.capture("see https://x.test at /tmp/app.log:3")
                #expect(app.tabTitles == ["file path", "url", "Plain Text"])
                app.capture(AppFixtures.monologLine)
                #expect(app.tabTitles == ["file path", "datetime", "json", "url", "Plain Text"])
            }
        }

        @Test func aTabRemembersItsEntryAndFallsBackWhenItShrinks() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("file path", 4)
                app.shortcut("1")
                app.shortcut("4")
                #expect(app.model.inspection.selection?.index == 4)

                app.capture(AppFixtures.monologLine.replacingOccurrences(of: "/vendor/", with: " vendor/"))
                app.shortcut("4")
                #expect(app.selectedTabTitle == "file path")
                #expect(app.model.selectedEntry != nil)
            }
        }

        @Test func tabMovesFocusToTheListArrowsStepAndReturnRunsTheFirstAction() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                app.shortcut("4")
                #expect(app.model.inspection.selection?.index == 0)

                app.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
                app.spin(0.2)
                #expect(app.inspectorHasFocus)
                #expect(app.textView.string == AppFixtures.monologLine)

                app.pressDown()
                app.pressDown()
                #expect(app.model.inspection.selection?.index == 2)
                app.pressUp()
                #expect(app.model.inspection.selection?.index == 1)

                app.pressReturn()
                #expect(app.openedFiles == [FileLocation(path: AppFixtures.backtraceFile, line: 80)])

                app.pressTab()
                #expect(app.panel.firstResponder === app.textView)

                app.textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
                app.spin(0.2)
                #expect(app.inspectorHasFocus)
            }
        }

        @Test func theRowsKnowWhenTheListHasKeyboardFocus() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                #expect(!app.model.listHasFocus)

                app.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
                app.spin(0.2)
                #expect(app.model.listHasFocus)

                app.pressTab()
                #expect(!app.model.listHasFocus)
            }
        }

        @Test func rowsDrawTheirOwnSelectionEvenWhenTheListAppearsWhileTyping() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.controller.show()
                app.spin(0.2)
                #expect(app.controller.entryList == nil)

                // Typing the first Match brings the Inspector and its list in.
                app.type(AppFixtures.monologLine, at: 0)
                app.waitForInspection()

                // The system's accent-colored highlight would cover the row's own tint.
                let list = try #require(app.controller.entryList)
                #expect(list.selectionHighlightStyle == .none)
            }
        }
    }

    @MainActor
    @Suite("Parsed views")
    struct DetailTests {
        @Test func aURLIsBrokenIntoPartsWithDecodedQueryParametersInOrder() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture("see https://a.test/x?q=a%20b&id=7&id=8#top for details")

                guard case .url(let url)? = app.model.selectedEntry?.detail else {
                    Issue.record("the URL isn't parsed")
                    return
                }
                #expect(url.host == "a.test")
                #expect(url.query.map { "\($0.name) = \($0.value)" } == ["q = a b", "id = 7", "id = 8"])
                #expect(url.fragment == "top")
            }
        }

        @Test func aFilePathSaysWhetherItExistsOnThisMac() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let real = app.store.fileURL.path
                app.capture("\(real):3 and /no/such/file.php:12:5")

                let paths = try #require(app.inspection.tabs.first { $0.title == "file path" }).entries
                guard case .filePath(let found) = paths[0].detail, case .filePath(let missing) = paths[1].detail else {
                    Issue.record("the paths aren't parsed")
                    return
                }
                #expect(found.exists && found.line == 3)
                #expect(!missing.exists && missing.line == 12 && missing.column == 5)
            }
        }

        @Test func anOffsetlessDatetimeIsAssumedLocalWithAUTCReread() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("datetime", 0)

                guard case .datetime(let datetime)? = app.model.selectedEntry?.detail else {
                    Issue.record("the datetime isn't parsed")
                    return
                }
                #expect(datetime.assumedLocal)
                #expect(datetime.asUTC?.isoUTC == "2026-10-07T11:17:10Z")
                app.model.readsDatetimeAsUTC = true
                app.shortcut("2")
                app.shortcut("1")
                #expect(!app.model.readsDatetimeAsUTC)
            }
        }
    }

    @MainActor
    @Suite("The Inspector while editing")
    struct EditingTests {
        @Test func typingAURLBeforeTheDatetimeKeepsTheTabOrder() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.type("https://x.test ", at: 0)

                #expect(app.tabTitles == ["datetime", "json", "url", "file path", "Plain Text"])
                #expect(app.inspection.tabs[2].entries.count == 2)
            }
        }

        @Test func aNewPatternAppendsItsTabBeforePlainText() async throws {
            try await runInApp {
                var config = Config.default
                config.patterns[5].enabled = true  // log level
                let app = try AppHarness(config: String(decoding: ConfigFile.encode(config), as: UTF8.self))
                defer { app.tearDown() }
                app.capture("2026-10-07 11:17:10 something happened")
                #expect(app.tabTitles == ["datetime", "Plain Text"])

                app.type("ERROR ", at: 0)
                #expect(app.tabTitles == ["datetime", "log level", "Plain Text"])

                app.capture("ERROR 2026-10-07 11:17:10 something happened")
                #expect(app.tabTitles == ["log level", "datetime", "Plain Text"])
            }
        }

        @Test func deletingTheOnlyDatetimeDropsItsTabAndFallsBackToTheJSON() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("datetime", 0)

                app.type("", replacing: app.range(of: "2026-10-07 11:17:10"))

                #expect(!app.tabTitles.contains("datetime"))
                #expect(app.selectedTabTitle == "json")
            }
        }

        @Test func editingInsideTheSelectedFilePathKeepsAFilePathSelected() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.select("file path", 3)

                app.type("Events2", replacing: app.range(of: "Illuminate/Events"))

                #expect(app.selectedTabTitle == "file path")
                #expect(app.model.selectedEntry?.text.contains("Events2") == true)
            }
        }

        @Test func pastingOverTheWholeInputOrdersTabsAfresh() async throws {
            try await runInApp {
                var config = Config.default
                config.patterns[5].enabled = true
                let app = try AppHarness(config: String(decoding: ConfigFile.encode(config), as: UTF8.self))
                defer { app.tearDown() }
                app.capture("2026-10-07 then ERROR")
                #expect(app.tabTitles == ["datetime", "log level", "Plain Text"])

                app.type("ERROR then 2026-10-07", replacing: NSRange(location: 0, length: (app.textView.string as NSString).length))
                #expect(app.tabTitles == ["log level", "datetime", "Plain Text"])
            }
        }

        @Test func disablingAPatternInTheConfigRemovesItsTab() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                var config = Config.default
                config.patterns[2].enabled = false  // url
                try app.writeConfig(String(decoding: ConfigFile.encode(config), as: UTF8.self))

                #expect(app.tabTitles == ["datetime", "json", "file path", "Plain Text"])
            }
        }
    }
}

extension AppTests {
    @MainActor
    @Suite("Grok")
    struct GrokPanelTests {
        @Test func theNginxAccessPatternInTheConfigFileShowsFourFieldsInThePanel() async throws {
            try await runInApp {
                let config = #"""
                { "patterns": [
                  { "name": "access", "regex": "%{IPV4:client} - - \\[%{HTTPDATE:time}\\] \"%{WORD:method} %{URIPATHPARAM:path}", "actions": ["copy"] }
                ] }
                """#
                let app = try AppHarness(config: config)
                defer { app.tearDown() }
                app.capture(#"203.0.113.7 - - [09/Oct/2026:10:15:32 +0700] "GET /api/v1/signin HTTP/1.1" 200 512"#)
                try app.select("access", 0)

                let fields = try #require(app.model.selectedEntry?.fields)
                #expect(fields.map(\.field.label) == ["client", "time", "method", "path"])
                fields[0].copy()
                #expect(app.copied == "203.0.113.7")
            }
        }
    }
}
