import AppKit
import SwiftUI
import Testing
import TextierCore
@testable import Textier

/// Not a test: captures the README demo's frames from the real app, for
/// `scripts/make-demo.sh`. It runs only with `TEXTIER_DEMO_FRAMES` set to the folder
/// the frames go to, and it takes the screen while it runs.
private let demoFolder = ProcessInfo.processInfo.environment["TEXTIER_DEMO_FRAMES"]

extension AppTests {
    @MainActor
    @Suite("Demo frames", .serialized)
    struct DemoFrames {
        @Test(.enabled(if: demoFolder != nil))
        func captureTheDemoFrames() async throws {
            try await runInApp {
                let folder = try #require(demoFolder)
                let app = try AppHarness()
                defer { app.tearDown() }
                Effects.present = { window in
                    window.alphaValue = 1
                    window.ignoresMouseEvents = false
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                }
                try app.writeConfig(Self.config)

                try Self.popoverFrames(app: app, folder: folder)
                try Self.panelFrames(app: app, folder: folder)
                try Self.settingsFrames(app: app, folder: folder)
            }
        }

        // MARK: The scenes

        /// The Selection Popover's view in a popover of its own, under a stand-in
        /// for the menu bar icon: the real icon may sit behind the notch.
        static func popoverFrames(app: AppHarness, folder: String) throws {
            let screen = try #require(NSScreen.main)
            let anchor = NSWindow(
                contentRect: NSRect(x: screen.visibleFrame.maxX - 700, y: screen.visibleFrame.maxY - 24, width: 22, height: 22),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            anchor.isReleasedWhenClosed = false
            anchor.backgroundColor = .clear
            anchor.level = .statusBar
            anchor.orderFrontRegardless()
            app.spin(0.3)
            // A capture of the window alone leaves its glass blank, so the screen
            // around it is captured, over black and over white.
            let backdrop = Backdrop(screen: screen)

            let model = SelectionPopoverModel()
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.contentSize = SelectionPopoverView.size
            popover.contentViewController = NSHostingController(rootView: SelectionPopoverView(
                model: model, openPanel: {}, close: {}
            ))
            model.show(selection: Sample.selection)
            NSApp.activate()
            popover.show(relativeTo: anchor.contentView!.bounds, of: anchor.contentView!, preferredEdge: .minY)
            let window = try #require(popover.contentViewController?.view.window)
            window.makeKey()
            model.didOpen()
            app.spin(0.8)
            try shoot(around: window, "popover-1-list", over: backdrop, app: app, folder: folder)

            let datetime = try #require(model.rows.first { $0.tab.title == "datetime" })
            model.toggle(datetime)
            try shoot(around: window, "popover-2-datetime", over: backdrop, app: app, folder: folder)

            let json = try #require(model.rows.first { $0.tab.title == "json" })
            model.toggle(json)
            try shoot(around: window, "popover-3-json", over: backdrop, app: app, folder: folder)

            popover.close()
            anchor.close()
            backdrop.window.close()
            app.spin(0.5)
        }

        static func panelFrames(app: AppHarness, folder: String) throws {
            let lines = Sample.log.components(separatedBy: "\n")
            for (frame, count) in [2, 4, lines.count].enumerated() {
                app.capture(lines.prefix(count).joined(separator: "\n"))
                if frame == 0 {
                    app.panel.setFrame(NSRect(x: 0, y: 0, width: 1240, height: 780), display: true)
                    app.panel.center()
                }
                app.waitForInspection()
                try shoot(app.panel, "panel-\(frame + 1)-input", app: app, folder: folder)
            }

            try app.select("datetime", 1)
            try shoot(app.panel, "panel-4-datetime", app: app, folder: folder)

            try app.select("json", 0)
            try shoot(app.panel, "panel-5-json", app: app, folder: folder)

            let field = try #require(app.panel.contentView.flatMap(searchField))
            for (frame, query) in ["$.items", "$.items[?@.qty > 1].sku"].enumerated() {
                field.stringValue = query
                field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
                app.spin(0.6)
                try shoot(app.panel, "panel-\(frame + 6)-jsonpath", app: app, folder: folder)
            }
        }

        static func settingsFrames(app: AppHarness, folder: String) throws {
            SettingsWindowController.show()
            let settings = try #require(SettingsWindowController.current)
            settings.model.section = .patterns
            settings.model.selectedPattern = settings.model.config.patterns.firstIndex { $0.name == "order id" }
            app.spin(0.6)
            try shoot(settings.window, "settings-1-pattern", app: app, folder: folder)
        }

        // MARK: Capturing

        static func shoot(_ window: NSWindow, _ name: String, app: AppHarness, folder: String) throws {
            app.spin(0.6)
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", "\(folder)/\(name).png"]
            try capture.run()
            capture.waitUntilExit()
            #expect(capture.terminationStatus == 0, "\(name)")
        }

        /// The screen around `window`, from the menu bar's foot down, over a black
        /// backdrop and a white one (`-black` and `-white`): the difference is how
        /// see-through each pixel is, which `scripts/make-demo.swift` works out.
        static func shoot(around window: NSWindow, _ name: String, over backdrop: Backdrop, app: AppHarness, folder: String) throws {
            app.spin(0.6)
            let screen = try #require(window.screen ?? NSScreen.main)
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            let frame = window.frame
            let rect = [frame.minX - 60, menuBar, frame.width + 120, screen.frame.maxY - frame.minY - menuBar + 60]
                .map { String(Int($0.rounded())) }.joined(separator: ",")
            for (shade, white) in [("black", 0.0), ("white", 1.0)] {
                backdrop.window.backgroundColor = NSColor(white: white, alpha: 1)
                app.spin(0.4)
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-R", rect, "\(folder)/\(name)-\(shade).png"]
                try capture.run()
                capture.waitUntilExit()
                #expect(capture.terminationStatus == 0, "\(name)")
            }
        }

        /// A window over the whole screen, under the popover.
        @MainActor
        final class Backdrop {
            let window: NSWindow

            init(screen: NSScreen) {
                window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.level = .floating
                window.orderFrontRegardless()
            }
        }

        static func searchField(in view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            for subview in view.subviews { if let found = searchField(in: subview) { return found } }
            return nil
        }

        // MARK: The text

        /// The shipped Patterns with the log level Preset on, a User Pattern for
        /// order ids, and the dark appearance.
        static var config: Config {
            var config = Config.default
            if let level = config.patterns.firstIndex(where: { $0.name == "log level" }) {
                config.patterns[level].enabled = true
            }
            config.patterns.append(Pattern(
                name: "order id", regex: #"\bORD-(?<number>\d{5})\b"#, actions: [.copy], color: "#d6409f"
            ))
            config.appearance = .dark
            return config
        }

        enum Sample {
            /// A log line `minutes` ago, as a logger writes it.
            static func at(_ minutes: Double, _ rest: String) -> String {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return formatter.string(from: Date().addingTimeInterval(-minutes * 60)) + " " + rest
            }

            static let payload = #"{"order":"ORD-10293","amount":42.5,"currency":"EUR","gateway":{"name":"stripe","status":502,"retry_after":30},"items":[{"sku":"TEE-M","qty":2},{"sku":"MUG-01","qty":1},{"sku":"CAP-BLK","qty":3}]}"#

            static var selection: String {
                [
                    at(3, "ERROR checkout.payment: charge failed " + payload),
                    at(2.9, "WARNING retrying https://api.example.com/v1/payments/ORD-10293?attempt=2"),
                    at(2.8, "INFO handler at /srv/shop/app/Payments/Gateway.php:118"),
                ].joined(separator: "\n")
            }

            static var log: String {
                let epoch = Int(Date().addingTimeInterval(-170).timeIntervalSince1970)
                return [
                    at(3.2, "DEBUG cache warmed: 1204 keys in 38ms"),
                    at(3, "ERROR checkout.payment: charge failed " + payload),
                    at(2.9, "WARNING retrying https://api.example.com/v1/payments/ORD-10293?attempt=2"),
                    at(2.8, "INFO handler at /srv/shop/app/Payments/Gateway.php:118"),
                    at(2.7, "NOTICE webhook queued for \(epoch) to https://hooks.example.com/stripe"),
                    at(2.5, "INFO order ORD-10293 marked for retry, see ~/logs/checkout.log:2041"),
                ].joined(separator: "\n")
            }
        }
    }
}
