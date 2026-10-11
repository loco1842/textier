import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppHarness {
    /// A harness whose config sets `inspectorLayout`.
    static func withLayout(_ layout: InspectorLayout) throws -> AppHarness {
        var config = Config.default
        config.inspectorLayout = layout
        return try AppHarness(config: String(decoding: ConfigFile.encode(config), as: UTF8.self))
    }

    /// The rows the Inspector's entry list shows (section headers included).
    var listRowCount: Int? {
        controller.entryList?.numberOfRows
    }
}

extension AppTests {
    @MainActor
    @Suite("The Inspector as one list")
    struct ListLayoutTests {
        @Test func tabsShowOnlyTheSelectedPatternsEntries() async throws {
            try await runInApp {
                let app = try AppHarness.withLayout(.tabs)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.model.layout == .tabs)
                #expect(app.listRowCount == 1)
            }
        }

        @Test func theListShowsEveryPatternAsASectionWithItsEntries() async throws {
            try await runInApp {
                let app = try AppHarness.withLayout(.list)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.model.layout == .list)
                // Five section headers (datetime, json, url, file path, Plain Text) and ten entries.
                #expect(app.listRowCount == 15)
                #expect(app.selectedTabTitle == "json")
            }
        }

        @Test func aSectionCollapsesAndSelectingIntoItExpandsItAgain() async throws {
            try await runInApp {
                let app = try AppHarness.withLayout(.list)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.model.setCollapsed(.pattern("datetime"), true)
                app.spin(0.2)
                #expect(app.listRowCount == 14)

                app.click(onText: "11:17:10")
                app.spin(0.2)
                #expect(app.selectedTabTitle == "datetime")
                #expect(!app.model.isCollapsed(.pattern("datetime")))
                #expect(app.listRowCount == 15)
            }
        }

        @Test func arrowsStepAcrossSectionsAndReturnRunsTheFirstAction() async throws {
            try await runInApp {
                let app = try AppHarness.withLayout(.list)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
                app.spin(0.2)
                #expect(app.inspectorHasFocus)
                app.pressDown()
                #expect(app.selectedTabTitle == "url")
                app.pressDown()
                #expect(app.selectedTabTitle == "file path")
                #expect(app.model.inspection.selection?.index == 0)

                app.pressReturn()
                #expect(app.openedFiles.count == 1)
            }
        }

        @Test func commandDigitsJumpToTheNthSection() async throws {
            try await runInApp {
                let app = try AppHarness.withLayout(.list)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.shortcut("4"))
                #expect(app.selectedTabTitle == "file path")
            }
        }

        @Test func switchingTheLayoutInTheConfigAppliesOnSave() async throws {
            try await runInApp {
                let app = try AppHarness.withLayout(.tabs)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                var config = Config.default
                config.inspectorLayout = .list
                try app.writeConfig(String(decoding: ConfigFile.encode(config), as: UTF8.self))
                app.spin(0.2)
                #expect(app.listRowCount == 15)
            }
        }
    
        @Test func commandLSwitchesTheLayoutAndItHoldsAcrossCaptures() async throws {
            try await runInApp {
                let app = try AppHarness.withLayout(.tabs)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.shortcut("l"))
                #expect(app.model.layout == .list)
                #expect(app.listRowCount == 15)

                app.capture(AppFixtures.monologLine)
                #expect(app.model.layout == .list)

                app.model.layout = .tabs
                app.spin(0.2)
                #expect(app.listRowCount == 1)
            }
        }

        @Test func aConfigReloadKeepsTheSwitchUnlessTheLayoutKeyChanged() async throws {
            try await runInApp {
                let app = try AppHarness.withLayout(.tabs)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                app.shortcut("l")

                var config = Config.default
                config.copyJSON = .pretty
                try app.writeConfig(String(decoding: ConfigFile.encode(config), as: UTF8.self))
                #expect(app.model.layout == .list)

                config.inspectorLayout = .list
                try app.writeConfig(String(decoding: ConfigFile.encode(config), as: UTF8.self))
                app.shortcut("l")
                #expect(app.model.layout == .tabs)
                config.inspectorLayout = .tabs
                try app.writeConfig(String(decoding: ConfigFile.encode(config), as: UTF8.self))
                config.inspectorLayout = .list
                try app.writeConfig(String(decoding: ConfigFile.encode(config), as: UTF8.self))
                #expect(app.model.layout == .list)
            }
        }
    }
}
