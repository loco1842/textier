import AppKit
import CryptoKit
import Synchronization
import TextierCore

/// Finds a newer textier release on GitHub and installs it (ADR-0005): at launch
/// and once a day while the Config's `checkForUpdates` is on, and whenever asked.
/// A release found is offered in a window (`UpdateWindow`); installing
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
        current: version(in: Bundle.main.infoDictionary),
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
    var canInstall: Bool { installProblem == nil }

    /// Why an update can't be installed here, when it can't: textier must run
    /// from its app, in a folder it can write to.
    var installProblem: String? {
        guard let appURL, current != nil else {
            return "textier isn't running from its app here, so it can't replace itself."
        }
        // Opened without clearing the quarantine flag, macOS runs a read-only copy.
        if appURL.path.contains("/AppTranslocation/") {
            return "macOS is running textier from a temporary copy, as its quarantine flag wasn't cleared. Download it from the release page, and clear the flag as the README says."
        }
        let folder = appURL.deletingLastPathComponent()
        if !isWritable(folder) { return "textier can't write to \(folder.path), so it can't replace itself there." }
        return nil
    }

    /// Whether files can be put in `folder`; the app tests answer for a folder of theirs.
    @ObservationIgnored var isWritable: (URL) -> Bool = { FileManager.default.isWritableFile(atPath: $0.path) }

    /// Fetches a URL's contents; the app tests answer instead of GitHub.
    @ObservationIgnored var fetch: @Sendable (URL) throws -> Data = Updater.download
    /// Quits and opens the app at the URL once quit; the app tests record it.
    @ObservationIgnored var relaunch: @MainActor (URL) -> Void = { Updater.relaunchApp($0) }
    /// Shows the update window: in front and key when asked for, or without
    /// taking the keyboard when a check found a release by itself.
    @ObservationIgnored var show: @MainActor (_ asked: Bool) -> Void = { UpdateWindow.show(activating: $0) }
    @ObservationIgnored var defaults = UserDefaults.standard
    @ObservationIgnored var now: () -> Date = Date.init

    /// Where the user defaults keep the last check and the version skipped.
    private enum Key {
        static let lastCheck = "lastUpdateCheck"
        static let skippedVersion = "skippedUpdateVersion"
    }

    /// The last check that reached GitHub, and the version the user skipped.
    var lastCheck: Date? { defaults.object(forKey: Key.lastCheck) as? Date }
    var skippedVersion: AppVersion? { defaults.string(forKey: Key.skippedVersion).flatMap(AppVersion.init) }

    /// Whether the check running was asked for, so its result shows whatever it is.
    private var isUserInitiated = false
    @ObservationIgnored private var timers: [Timer] = []
    private static let work = DispatchQueue(label: "textier.updates", qos: .utility)

    init(current: AppVersion?, appURL: URL?, bundleIdentifier: String?) {
        self.current = current
        self.appURL = appURL
        self.bundleIdentifier = bundleIdentifier
    }

    // MARK: Checking

    /// Starts the automatic checks: one a few seconds after launch, then each hour
    /// one that goes ahead when a day has passed since the last that worked.
    func start() {
        let launch = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAutomatically() }
        }
        let hourly = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        for timer in [launch, hourly] {
            RunLoop.main.add(timer, forMode: .common)
            timers.append(timer)
        }
    }

    /// The daily check, when a day has passed since the last.
    func checkIfDue(enabled: Bool = AppConfig.current.checkForUpdates) {
        guard isUpdateCheckDue(lastCheck: lastCheck, now: now()) else { return }
        checkAutomatically(enabled: enabled)
    }

    /// A check textier makes by itself, while they're on; only an app bundle makes them.
    func checkAutomatically(enabled: Bool = AppConfig.current.checkForUpdates) {
        guard enabled, current != nil, state == .idle else { return }
        check(userInitiated: false)
    }

    /// Asks GitHub for the latest release. One asked for shows the window at once
    /// and whatever it finds; an automatic one shows only a release to offer.
    func check(userInitiated: Bool) {
        switch state {
        case .checking, .installing:
            if userInitiated {
                isUserInitiated = true
                show(true)
            }
            return
        default:
            break
        }
        isUserInitiated = userInitiated
        state = .checking
        if userInitiated { show(true) }
        let fetch = fetch
        Self.work.async { [weak self] in
            let result = Result { () throws -> Release in
                let data = try fetch(Self.latestRelease)
                guard let release = String(data: data, encoding: .utf8).flatMap(Release.init(gitHubJSON:)) else {
                    throw UpdateError.notARelease
                }
                return release
            }
            onMain { self?.finishCheck(result) }
        }
    }

    private func finishCheck(_ result: Result<Release, any Error>) {
        guard state == .checking else { return }
        switch result {
        case .success(let release):
            defaults.set(now(), forKey: Key.lastCheck)
            // A development build (no version) is older than any release.
            let current = current ?? AppVersion("0.0.0-dev")!
            switch updateCheck(current: current, latest: release, skipped: isUserInitiated ? nil : skippedVersion) {
            case .available(let release):
                state = .available(release)
                show(isUserInitiated)
            case .upToDate:
                state = isUserInitiated ? .upToDate : .idle
            case .skipped:
                state = .idle
            }
        case .failure(let error):
            // An automatic check tries again in an hour, quietly.
            state = isUserInitiated ? .failed(Self.describe(error), page: Self.releasesPage) : .idle
        }
    }

    // MARK: Answering an offer

    func skip(_ release: Release) {
        defaults.set(release.version.description, forKey: Key.skippedVersion)
        state = .idle
    }

    /// Later, OK, or the window closed: nothing until the next check.
    func dismiss() {
        if case .installing = state { return }
        state = .idle
    }

    /// Downloads `release`, checks it, puts it in place of the app and relaunches.
    func install(_ release: Release) {
        guard installProblem == nil, let appURL, let identifier = bundleIdentifier else {
            state = .failed(installProblem ?? "textier can't replace itself here.", page: release.page)
            return
        }
        state = .installing(release, step: "Downloading textier \(release.version)…")
        let fetch = fetch
        Self.work.async { [weak self] in
            let result = Result {
                try Self.replace(appURL, with: release, identifier: identifier, fetch: fetch) { step in
                    onMain {
                        guard let self, case .installing(let installing, _) = self.state, installing == release else { return }
                        self.state = .installing(release, step: step)
                    }
                }
            }
            onMain {
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

    /// A version string from an app's Info.plist.
    nonisolated static func version(in info: [String: Any]?) -> AppVersion? {
        (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
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
        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == identifier, version(in: info) == release.version
        else { throw UpdateError.notTextier(release.version) }
        // Downloaded by textier, not a browser, it shouldn't be quarantined; made sure.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        do {
            _ = try files.replaceItemAt(appURL, withItemAt: newApp)
        } catch {
            throw UpdateError.replace(path: appURL.path, reason: error.localizedDescription)
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
    case replace(path: String, reason: String)

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

/// Runs `work` on the main thread, from the updates queue.
private func onMain(_ work: @escaping @Sendable @MainActor () -> Void) {
    RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated(work) }
}
