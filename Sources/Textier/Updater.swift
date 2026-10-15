import AppKit
import CryptoKit
import Synchronization
import SwiftUI
import TextierCore

/// Finds a newer textier release on GitHub and installs it (ADR-0005): at launch
/// and once a day while the Config's `checkForUpdates` is on, and whenever asked.
/// A release found is offered in a window (`UpdateWindowController`); installing
/// downloads its zip, checks it against the release's `SHA256SUMS.txt`, puts it in
/// place of the running app and relaunches. Anything wrong leaves the app as it was.
@MainActor @Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        /// After a check asked for: nothing newer.
        case upToDate
        case available(Release)
        case installing(Release, step: String)
        /// After a check asked for, or an install: what went wrong, and where to
        /// download the release by hand.
        case failed(String, page: URL?)
    }

    /// The running app's.
    static let shared = Updater(
        current: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
        appURL: Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil,
        bundleIdentifier: Bundle.main.bundleIdentifier
    )

    /// Where releases are listed: the latest one, drafts and pre-releases left out.
    static let latestRelease = URL(string: "https://api.github.com/repos/loco1842/textier/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/loco1842/textier/releases")!

    private(set) var state = State.idle
    /// The running version; nil outside an app bundle (`swift run`).
    let current: AppVersion?
    /// The app bundle the update replaces; nil outside one.
    let appURL: URL?
    let bundleIdentifier: String?
    /// Whether an update can be installed here, not only downloaded by hand.
    var canInstall: Bool { appURL != nil && current != nil }

    /// Fetches a URL's contents; the app tests answer instead of GitHub.
    @ObservationIgnored var fetch: @Sendable (URL) throws -> Data = Updater.download
    /// Quits and opens the app at the URL once quit; the app tests record it.
    @ObservationIgnored var relaunch: @MainActor (URL) -> Void = { Updater.relaunchApp($0) }
    /// Shows the update window.
    @ObservationIgnored var show: @MainActor () -> Void = { UpdateWindowController.show() }
    @ObservationIgnored var defaults = UserDefaults.standard
    @ObservationIgnored var now: () -> Date = Date.init

    /// The last check that reached GitHub, and the version the user skipped.
    var lastCheck: Date? { defaults.object(forKey: "lastUpdateCheck") as? Date }
    var skippedVersion: String? { defaults.string(forKey: "skippedUpdateVersion") }

    /// Whether the check running was asked for, so its result shows whatever it is.
    private var isAskedFor = false
    @ObservationIgnored private var timers: [Timer] = []
    private static let work = DispatchQueue(label: "textier.updates", qos: .utility)

    init(current: AppVersion?, appURL: URL?, bundleIdentifier: String?) {
        self.current = current
        self.appURL = appURL
        self.bundleIdentifier = bundleIdentifier
    }

    // MARK: Checking

    /// Starts the automatic checks: one a few seconds after launch, then each hour,
    /// each going ahead only when a day has passed since the last that worked.
    func start() {
        for (interval, repeats) in [(5.0, false), (3600.0, true)] {
            let timer = Timer(timeInterval: interval, repeats: repeats) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkIfDue() }
            }
            RunLoop.main.add(timer, forMode: .common)
            timers.append(timer)
        }
    }

    /// An automatic check, when it's on and due; only an app bundle checks by itself.
    func checkIfDue(enabled: Bool = AppConfig.current.checkForUpdates) {
        guard enabled, current != nil, state == .idle, isUpdateCheckDue(lastCheck: lastCheck, now: now()) else { return }
        check(userInitiated: false)
    }

    /// Asks GitHub for the latest release. One asked for shows the window at once
    /// and whatever it finds; an automatic one shows only a release to offer.
    func check(userInitiated: Bool) {
        switch state {
        case .checking, .installing:
            if userInitiated {
                isAskedFor = true
                show()
            }
            return
        default:
            break
        }
        isAskedFor = userInitiated
        state = .checking
        if userInitiated { show() }
        let fetch = fetch
        Self.work.async { [weak self] in
            let result = Result { () throws -> Release in
                let data = try fetch(Self.latestRelease)
                guard let release = String(data: data, encoding: .utf8).flatMap(Release.init(gitHubJSON:)) else {
                    throw UpdateError.notARelease
                }
                return release
            }
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated { self?.finishCheck(result) }
            }
        }
    }

    private func finishCheck(_ result: Result<Release, any Error>) {
        guard state == .checking else { return }
        switch result {
        case .success(let release):
            defaults.set(now(), forKey: "lastUpdateCheck")
            // A development build (no version) is older than any release.
            let current = current ?? AppVersion("0.0.0-dev")!
            switch updateCheck(current: current, latest: release, skipped: isAskedFor ? nil : skippedVersion) {
            case .available(let release):
                state = .available(release)
                show()
            case .upToDate:
                state = isAskedFor ? .upToDate : .idle
            case .skipped:
                state = .idle
            }
        case .failure(let error):
            // An automatic check tries again in an hour, quietly.
            state = isAskedFor ? .failed(Self.describe(error), page: Self.releasesPage) : .idle
        }
    }

    // MARK: Answering an offer

    func skip(_ release: Release) {
        defaults.set(release.version.description, forKey: "skippedUpdateVersion")
        state = .idle
    }

    /// Later, OK, or the window closed: nothing until the next check.
    func dismiss() {
        if case .installing = state { return }
        state = .idle
    }

    /// Downloads `release`, checks it, puts it in place of the app and relaunches.
    func install(_ release: Release) {
        guard let appURL, let identifier = bundleIdentifier else {
            state = .failed("textier isn't running from its app here, so it can't replace itself.", page: release.page)
            return
        }
        state = .installing(release, step: "Downloading textier \(release.version)…")
        let fetch = fetch
        Self.work.async { [weak self] in
            let result = Result {
                try Self.replace(appURL, with: release, identifier: identifier, fetch: fetch) { step in
                    RunLoop.main.perform(inModes: [.common]) {
                        MainActor.assumeIsolated {
                            guard let self, case .installing(let installing, _) = self.state, installing == release else { return }
                            self.state = .installing(release, step: step)
                        }
                    }
                }
            }
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.state = .installing(release, step: "Relaunching…")
                        self.relaunch(appURL)
                    case .failure(let error):
                        self.state = .failed(Self.describe(error), page: release.page)
                    }
                }
            }
        }
    }

    // MARK: Installing, off the main thread

    /// Downloads the release's zip and checksums, checks and unzips it, and swaps
    /// it in for the app at `appURL`; throws, leaving the app as it was, when any
    /// step fails.
    nonisolated static func replace(
        _ appURL: URL, with release: Release, identifier: String, fetch: (URL) throws -> Data,
        step: (String) -> Void
    ) throws {
        guard let archive = release.archive, let sumsURL = release.checksums else { throw UpdateError.noArchive }
        let sums = String(decoding: try fetch(sumsURL), as: UTF8.self)
        guard let expected = checksum(of: archive.name, in: sums) else { throw UpdateError.noChecksum(archive.name) }
        let zip = try fetch(archive.url)
        step("Checking the download…")
        let actual = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError.checksumMismatch }

        // Staged beside the app, on its volume, so the swap is a rename.
        let files = FileManager.default
        let staging = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        defer { try? files.removeItem(at: staging) }
        let zipURL = staging.appendingPathComponent(archive.name)
        try zip.write(to: zipURL)
        let unzipped = staging.appendingPathComponent("unzipped")
        step("Installing…")
        guard try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unzipped.path]) == 0,
              let newApp = try files.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.unzip }
        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == identifier,
              (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) == release.version
        else { throw UpdateError.notTextier(release.version) }
        // Downloaded by textier, not a browser, it shouldn't be quarantined; made sure.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        do {
            _ = try files.replaceItemAt(appURL, withItemAt: newApp)
        } catch {
            throw UpdateError.replace(appURL.path, error.localizedDescription)
        }
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// A URL's contents over HTTPS, waiting for them (on the updates queue).
    nonisolated static func download(_ url: URL) throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        // GitHub's API turns away requests without one.
        request.setValue("textier", forHTTPHeaderField: "User-Agent")
        if url.host == "api.github.com" { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        let result = Mutex<Result<Data, any Error>?>(nil)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            let outcome: Result<Data, any Error>
            if let error {
                outcome = .failure(UpdateError.network(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                outcome = .failure(UpdateError.network("GitHub answered \(http.statusCode)"))
            } else {
                outcome = .success(data ?? Data())
            }
            result.withLock { $0 = outcome }
            done.signal()
        }.resume()
        done.wait()
        return try result.withLock { $0! }.get()
    }

    /// Opens the app at `url` once this one has quit, then quits.
    static func relaunchApp(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#,
            "sh", String(ProcessInfo.processInfo.processIdentifier), url.path,
        ]
        try? process.run()
        NSApp.terminate(nil)
    }

    nonisolated private static func describe(_ error: any Error) -> String {
        (error as? UpdateError)?.description ?? error.localizedDescription
    }
}

/// Why a check or an install failed, as the update window says it.
enum UpdateError: Error, CustomStringConvertible {
    case network(String)
    case notARelease
    case noArchive
    case noChecksum(String)
    case checksumMismatch
    case unzip
    case notTextier(AppVersion)
    case replace(String, String)

    var description: String {
        switch self {
        case .network(let reason): "Couldn't reach GitHub: \(reason)."
        case .notARelease: "GitHub's answer wasn't a textier release."
        case .noArchive: "The release has no textier zip to install."
        case .noChecksum(let name): "The release's SHA256SUMS.txt has no checksum for \(name)."
        case .checksumMismatch: "The download didn't match its checksum, so it wasn't installed."
        case .unzip: "The download couldn't be unzipped."
        case .notTextier(let version): "The download isn't textier \(version)."
        case .replace(let path, let reason): "textier couldn't replace itself at \(path): \(reason)"
        }
    }
}

// MARK: The window

/// The update window: what a check found, and the offer to install it.
@MainActor
enum UpdateWindowController {
    private static var window: NSWindow?

    static func show() {
        if let window {
            Effects.present(window)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 200), styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Software Update"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UpdateView(updater: .shared) { close() })
        window.center()
        Self.window = window
        closing = NotificationObservation(NSWindow.willCloseNotification, object: window) {
            Updater.shared.dismiss()
            Self.window = nil
        }
        Effects.present(window)
    }

    static func close() {
        window?.close()
    }

    private static var closing: NotificationObservation?
}

struct UpdateView: View {
    let updater: Updater
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var content: some View {
        switch updater.state {
        case .idle, .checking:
            Text("Looking for updates…").font(.headline)
            ProgressView().controlSize(.small)
        case .upToDate:
            Text("textier is up to date").font(.headline)
            Text("Version \(updater.current?.description ?? "") is the latest.").foregroundStyle(.secondary)
            buttons { Button("OK", action: close).keyboardShortcut(.defaultAction) }
        case .available(let release):
            available(release)
        case .installing(let release, let step):
            Text("Updating textier to \(release.version)").font(.headline)
            ProgressView(step).controlSize(.small)
        case .failed(let message, let page):
            Text("Couldn't update textier").font(.headline)
            Text(message).foregroundStyle(.secondary).textSelection(.enabled)
            buttons {
                if let page { Button("Open the Release Page") { Effects.openURL(page); close() } }
                Button("OK", action: close).keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder private func available(_ release: Release) -> some View {
        Text("textier \(release.version) is available").font(.headline)
        Text(updater.current.map { "You have \($0)." } ?? "This is a development build.").foregroundStyle(.secondary)
        if !release.notes.isEmpty {
            ScrollView {
                Text(Self.notes(release.notes))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(height: 180)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
        Text("After it relaunches, macOS asks for Accessibility again: textier isn't signed with a Developer ID.")
            .font(.callout)
            .foregroundStyle(.secondary)
        HStack {
            Button("Skip This Version") { updater.skip(release); close() }
            Spacer()
            Button("Later") { close() }
            if updater.canInstall {
                Button("Install and Relaunch") { updater.install(release) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Open the Release Page") { Effects.openURL(release.page); close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 4)
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
        }
        .padding(.top, 4)
    }

    /// Release notes in Markdown, inline styles kept, headings in bold and list
    /// items as bullets.
    static func notes(_ markdown: String) -> AttributedString {
        let text = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let heading = line.drop { $0 == "#" }
            if heading.count < line.count, heading.first == " " { return "**\(heading.dropFirst())**" }
            let indent = line.prefix { $0 == " " }
            let item = line.dropFirst(indent.count)
            if item.hasPrefix("* ") || item.hasPrefix("- ") { return indent + "• " + item.dropFirst(2) }
            return String(line)
        }.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(markdown)
    }
}
