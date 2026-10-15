import AppKit
import CryptoKit
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor @Suite("Updates")
    struct UpdaterTests {
        static let identifier = "local.textier.Textier"
        static let zipURL = URL(string: "https://example.test/textier-0.3.0.zip")!
        static let sumsURL = URL(string: "https://example.test/SHA256SUMS.txt")!

        static let releaseJSON = #"""
        {
          "tag_name": "v0.3.0", "draft": false, "prerelease": false,
          "html_url": "https://github.com/loco1842/textier/releases/tag/v0.3.0",
          "body": "## What's new\n- **Folding**",
          "assets": [
            { "name": "textier-0.3.0.zip", "browser_download_url": "https://example.test/textier-0.3.0.zip" },
            { "name": "SHA256SUMS.txt", "browser_download_url": "https://example.test/SHA256SUMS.txt" }
          ]
        }
        """#

        /// An app bundle like textier's at `folder/Textier.app`, its version and a
        /// file saying which build it is.
        @discardableResult
        func makeApp(in folder: URL, version: String, build: String, identifier: String = identifier) throws -> URL {
            let app = folder.appendingPathComponent("Textier.app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
            let info: NSDictionary = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version]
            try info.write(to: contents.appendingPathComponent("Info.plist"))
            try Data(build.utf8).write(to: contents.appendingPathComponent("Resources/build.txt"))
            return app
        }

        func build(of app: URL) -> String? {
            try? String(contentsOf: app.appendingPathComponent("Contents/Resources/build.txt"), encoding: .utf8)
        }

        /// The new release zipped as the release workflow zips it.
        func zipOfNewApp(in folder: URL, identifier: String = identifier) throws -> Data {
            let source = folder.appendingPathComponent("new")
            let app = try makeApp(in: source, version: "0.3.0", build: "new", identifier: identifier)
            let zip = folder.appendingPathComponent("new.zip")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
            try process.run()
            process.waitUntilExit()
            return try Data(contentsOf: zip)
        }

        /// An Updater for textier 0.2.0 installed in `folder`, with GitHub's answers.
        func updater(in folder: URL, answers: [URL: Data]) throws -> (Updater, URL) {
            let installed = try makeApp(in: folder.appendingPathComponent("Applications"), version: "0.2.0", build: "old")
            let updater = Updater(current: AppVersion("0.2.0"), appURL: installed, bundleIdentifier: Self.identifier)
            updater.fetch = { url in
                guard let data = answers[url] else { throw UpdateError.network("no answer for \(url)") }
                return data
            }
            updater.show = { _ in }
            updater.isWritable = { _ in true }
            let defaults = UserDefaults(suiteName: "textier.tests.\(UUID().uuidString)")!
            updater.defaults = defaults
            return (updater, installed)
        }

        func wait(_ app: AppHarness, until done: () -> Bool) {
            for _ in 0..<100 where !done() { app.spin(0.05) }
        }

        func waitUntilFailed(_ app: AppHarness, _ updater: Updater) {
            wait(app) { if case .failed = updater.state { true } else { false } }
        }

        func sums(for zip: Data) -> Data {
            let hash = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
            return Data("\(hash)  textier-0.3.0.zip\n\(String(repeating: "0", count: 64))  textier-0.3.0.dmg\n".utf8)
        }

        @Test func aCheckFindsANewerReleaseAndInstallsIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let zip = try zipOfNewApp(in: app.folder)
                let (updater, installed) = try updater(in: app.folder, answers: [
                    Updater.latestRelease: Data(Self.releaseJSON.utf8), Self.zipURL: zip, Self.sumsURL: sums(for: zip),
                ])
                var shown = 0
                updater.show = { _ in shown += 1 }
                var relaunched: [URL] = []
                updater.relaunch = { relaunched.append($0) }

                updater.check(userInitiated: true)
                #expect(updater.state == .checking)
                wait(app) { updater.state != .checking }
                guard case .available(let release) = updater.state else {
                    Issue.record("not offered: \(updater.state)")
                    return
                }
                #expect(release.version == AppVersion("0.3.0"))
                #expect(updater.lastCheck != nil)
                #expect(shown == 2)

                updater.install(release)
                wait(app) { !relaunched.isEmpty }
                #expect(relaunched == [installed])
                #expect(build(of: installed) == "new")
                let info = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))
                #expect(info?["CFBundleShortVersionString"] as? String == "0.3.0")
            }
        }

        @Test func aDownloadThatDoesntMatchItsChecksumChangesNothing() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let zip = try zipOfNewApp(in: app.folder)
                let (updater, installed) = try updater(in: app.folder, answers: [
                    Self.zipURL: zip, Self.sumsURL: sums(for: Data("something else".utf8)),
                ])
                var relaunched = false
                updater.relaunch = { _ in relaunched = true }
                let release = try #require(Release(gitHubJSON: Self.releaseJSON))
                updater.install(release)
                waitUntilFailed(app, updater)
                #expect(updater.state == .failed(UpdateError.checksumMismatch.description, page: release.page))
                #expect(build(of: installed) == "old")
                #expect(!relaunched)
            }
        }

        @Test func anotherAppInTheZipIsntInstalled() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let zip = try zipOfNewApp(in: app.folder, identifier: "com.example.other")
                let (updater, installed) = try updater(in: app.folder, answers: [Self.zipURL: zip, Self.sumsURL: sums(for: zip)])
                updater.relaunch = { _ in Issue.record("relaunched") }
                let release = try #require(Release(gitHubJSON: Self.releaseJSON))
                updater.install(release)
                waitUntilFailed(app, updater)
                #expect(updater.state == .failed(UpdateError.notTextier(release.version).description, page: release.page))
                #expect(build(of: installed) == "old")
            }
        }

        @Test func upToDateShowsOnlyWhenAskedAndChecksRunDailyWhileOn() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let current = Self.releaseJSON.replacingOccurrences(of: "v0.3.0\"", with: "v0.2.0\"")
                let (updater, _) = try updater(in: app.folder, answers: [Updater.latestRelease: Data(current.utf8)])
                var shown = 0
                updater.show = { _ in shown += 1 }

                updater.check(userInitiated: true)
                wait(app) { updater.state != .checking }
                #expect(updater.state == .upToDate)
                updater.dismiss()

                // Automatic: due only a day after the last check, and only while on.
                updater.checkIfDue(enabled: true)
                #expect(updater.state == .idle)
                // At launch, whenever it's on, however recent the last.
                updater.checkAutomatically(enabled: false)
                #expect(updater.state == .idle)
                updater.checkAutomatically(enabled: true)
                #expect(updater.state == .checking)
                wait(app) { updater.state != .checking }
                #expect(updater.state == .idle)
                updater.now = { Date().addingTimeInterval(90_000) }
                updater.checkIfDue(enabled: false)
                #expect(updater.state == .idle)
                shown = 0
                updater.checkIfDue(enabled: true)
                #expect(updater.state == .checking)
                wait(app) { updater.state != .checking }
                // Nothing newer: nothing shows.
                #expect(updater.state == .idle)
                #expect(shown == 0)
            }
        }

        @Test func aSkippedVersionIsOfferedOnlyWhenAsked() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let (updater, _) = try updater(in: app.folder, answers: [Updater.latestRelease: Data(Self.releaseJSON.utf8)])
                updater.skip(try #require(Release(gitHubJSON: Self.releaseJSON)))
                #expect(updater.skippedVersion == AppVersion("0.3.0"))

                updater.checkIfDue(enabled: true)
                wait(app) { updater.state != .checking }
                #expect(updater.state == .idle)
                updater.check(userInitiated: true)
                wait(app) { updater.state != .checking }
                if case .available = updater.state {} else { Issue.record("not offered when asked: \(updater.state)") }
            }
        }

        @Test func anOfferFoundByItselfDoesntTakeTheKeyboard() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let (updater, _) = try updater(in: app.folder, answers: [Updater.latestRelease: Data(Self.releaseJSON.utf8)])
                var shows: [Bool] = []
                updater.show = { shows.append($0) }
                updater.checkIfDue(enabled: true)
                wait(app) { updater.state != .checking }
                updater.dismiss()
                updater.check(userInitiated: true)
                wait(app) { updater.state != .checking }
                // Automatic: in the background; asked for: in front, as it starts and as it finds.
                #expect(shows == [false, true, true])
            }
        }

        @Test func whereItCantReplaceItselfItSaysWhyAndOffersTheReleasePage() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let (updater, installed) = try updater(in: app.folder, answers: [:])
                #expect(updater.canInstall)
                updater.isWritable = { _ in false }
                #expect(updater.installProblem == "textier can't write to \(installed.deletingLastPathComponent().path), so it can't replace itself there.")
                let release = try #require(Release(gitHubJSON: Self.releaseJSON))
                updater.install(release)
                #expect(updater.state == .failed(updater.installProblem!, page: release.page))

                let translocated = Updater(
                    current: AppVersion("0.2.0"),
                    appURL: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Textier.app"),
                    bundleIdentifier: Self.identifier
                )
                #expect(translocated.installProblem?.hasPrefix("macOS is running textier from a temporary copy") == true)
                #expect(Updater(current: nil, appURL: nil, bundleIdentifier: nil).installProblem != nil)
            }
        }

        @Test func settingsTurnsTheDailyCheckOffAndOn() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                #expect(settings.config.checkForUpdates)
                settings.setCheckForUpdates(false)
                #expect(app.configText.contains(#""checkForUpdates": false"#))
                #expect(!app.store.config.checkForUpdates)
                settings.setCheckForUpdates(true)
                #expect(app.store.config.checkForUpdates)
            }
        }

        @Test func releaseNotesShowHeadingsInBoldAndListsAsBullets() {
            let notes = String(UpdateView.notes("## What's Changed\n* Folding\n  - nested\n**Full** text").characters)
            #expect(notes == "What's Changed\n• Folding\n  • nested\nFull text")
        }

        @Test func aFailedCheckSaysSoOnlyWhenAsked() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let (updater, _) = try updater(in: app.folder, answers: [:])
                updater.checkIfDue(enabled: true)
                wait(app) { updater.state != .checking }
                #expect(updater.state == .idle)
                // Not counted as a check: the next one tries again.
                #expect(updater.lastCheck == nil)

                updater.check(userInitiated: true)
                wait(app) { updater.state != .checking }
                guard case .failed(let message, let page) = updater.state else {
                    Issue.record("\(updater.state)")
                    return
                }
                #expect(message.hasPrefix("Couldn't reach GitHub"))
                #expect(page == Updater.releasesPage)
            }
        }

    }
}
