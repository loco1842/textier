import AppKit
import TextierCore
import UniformTypeIdentifiers

/// Opens files in the user's editor, through `EditorCommand` and the config's
/// `editorCommand`.
///
/// GUI apps don't inherit shell exports, so at launch textier asks the user's login
/// shell once for `$EDITOR` and `$PATH` and caches both. Commands then run with that
/// `PATH` rather than through a login shell per open, which would add the shell's
/// startup time to every click. If a command can't be found, can't launch or exits
/// with an error, the file opens with its default app instead, or shows in Finder
/// when that app could run it or act on it (`openWithoutEditor`), and a warning in
/// the Panel footer and on the menu bar icon says so, so a typo in `editorCommand`
/// doesn't go unnoticed.
@MainActor
enum Editor {
    private static var didPrepare = false
    /// The login shell's environment, once it's been read.
    private static var environment: ShellEnvironment?
    /// Opens waiting for the environment, and the timer that stops them waiting.
    private static var waiting: [(ShellEnvironment) -> Void] = []
    private static var patience: Timer?
    /// How long an open waits for the environment before going ahead without it.
    private static let patienceInterval: TimeInterval = 3

    /// Starts resolving the login shell's environment in the background.
    static func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        let reading = Task.detached { ShellEnvironment.fromLoginShell() }
        Task {
            let shell = await reading.value
            environment = shell
            patience?.invalidate()
            settle(with: shell)
        }
    }

    /// Runs `body` with the environment: at once when it's known, else once it is,
    /// or after `patienceInterval` with none (the app's own `PATH`, no `$EDITOR`),
    /// so a slow login shell delays an open but never swallows it.
    private static func withEnvironment(_ body: @escaping (ShellEnvironment) -> Void) {
        if let environment { return body(environment) }
        waiting.append(body)
        guard patience == nil else { return }
        let timer = Timer(timeInterval: patienceInterval, repeats: false) { _ in
            MainActor.assumeIsolated {
                NSLog("textier: the login shell's environment isn't ready; opening without it")
                settle(with: ShellEnvironment())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        patience = timer
    }

    private static func settle(with shell: ShellEnvironment) {
        patience = nil
        let ready = waiting
        waiting = []
        for body in ready { body(shell) }
    }

    /// Opens `path` (`~/` already expanded), at `line` when given.
    static func open(path: String, line: Int?) {
        prepare()
        withEnvironment { shell in
            let arguments = EditorCommand.arguments(
                template: AppConfig.current.editorCommand, editor: shell.editor, path: path, line: line
            )
            run(arguments, path: shell.path) { failure in
                guard let failure else {
                    AppConfig.store.editorWarning = nil
                    return
                }
                let fallback = openWithoutEditor(path)
                AppConfig.store.editorWarning = ConfigWarning(
                    "Couldn't run `\(arguments.joined(separator: " "))` (\(failure)); \(fallback)"
                )
            }
        }
    }

    /// When the editor can't open `path`: opens it with the default app if that
    /// only shows it, else shows it in Finder, and does neither when there's no
    /// file there. Says which, for the warning.
    ///
    /// The path comes from a Match, so from any text at all, and the default app of
    /// many files acts on them: an app launches, Terminal runs a `.command` or
    /// `.tool`, Installer starts a `.pkg`, a `.jnlp` runs Java from the web, a
    /// `.mobileconfig` installs a profile, a browser runs an `.html` or `.svg`'s
    /// scripts, Calendar and Contacts import an `.ics` or `.vcf`. So only the types
    /// in `shownByDefaultApp` open.
    static func openWithoutEditor(_ path: String) -> String {
        guard FileManager.default.fileExists(atPath: path) else { return "the file doesn't exist" }
        let url = URL(fileURLWithPath: path)
        if opensWithDefaultApp(url) {
            Effects.openWithDefaultApp(url)
            return "opened it with the default app"
        }
        Effects.revealInFinder(url)
        return "showed it in Finder"
    }

    /// Whether `url` is a file its default app only shows (see `openWithoutEditor`):
    /// not a folder or package, of a type in `shownByDefaultApp`, an image other
    /// than an SVG, and not a script, whose text Terminal, a launcher or Script
    /// Editor would run or act on rather than show. Python, Ruby, PHP and the like
    /// are typed as shell scripts, though they're source code and plain text too.
    static func opensWithDefaultApp(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey]),
              values.isDirectory == false, values.isPackage != true, let type = values.contentType
        else { return false }
        guard ![.shellScript, .appleScript, .osaScript].contains(where: type.conforms) else { return false }
        if type.conforms(to: .image) { return !type.conforms(to: .svg) }
        return shownByDefaultApp.contains(where: type.conforms)
    }

    /// Types whose default app only shows them. Not `.text` as a whole: HTML, XML
    /// (`.jnlp`, `.mobileconfig`), calendars and contact cards are text too.
    private static let shownByDefaultApp: [UTType] = [
        .plainText, .sourceCode, .json, .yaml, .log, .commaSeparatedText, .pdf,
    ]

    /// Runs `arguments` via `/usr/bin/env`, which looks the executable up on `path`,
    /// and reports why it failed, or nil when it exited cleanly. CLI launchers
    /// (`cursor`, `code`) hand the file to the editor and exit; one that keeps running
    /// (`code --wait`) never reports, which is fine, since it found its editor.
    private static func run(_ arguments: [String], path: String?, completion: @escaping @MainActor (String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        if let path { environment["PATH"] = path }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            let status = process.terminationStatus
            let failure: String? = switch process.terminationReason {
            case .exit where status == 0: nil
            case .exit: status == 127 ? "command not found" : "exit \(status)"
            default: "killed by signal \(status)"
            }
            if let failure { NSLog("textier: %@ failed: %@", arguments.joined(separator: " "), failure) }
            Task { @MainActor in completion(failure) }
        }
        do {
            try process.run()
        } catch {
            NSLog("textier: couldn't run %@: %@", arguments.joined(separator: " "), error.localizedDescription)
            completion(error.localizedDescription)
        }
    }
}

/// `$EDITOR` and `$PATH` as the user's login shell sets them.
struct ShellEnvironment: Sendable {
    var editor: String?
    var path: String?

    private static let marker = "__textier_env__"
    private static let timeout = DispatchTimeInterval.seconds(10)

    /// Runs `$SHELL -l -i -c` (zsh when unset) and reads the two variables back.
    /// The shell is interactive too, because `EDITOR` and `PATH` are commonly set in
    /// `.zshrc`, which a non-interactive login shell skips. Its stdin is empty, so
    /// nothing in the rc files can wait for input, and a marker separates the values
    /// from anything the rc files print. A heavy rc setup takes a couple of seconds,
    /// so this runs off the main thread at launch and gives up after ten.
    nonisolated static func fromLoginShell() -> ShellEnvironment {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-i", "-c", #"printf '\#(marker)%s\0%s\0' "$EDITOR" "$PATH""#]
        let output = Pipe()
        let collected = Collected()
        // Signalled once the values are in, or at the end of the output.
        let read = DispatchSemaphore(value: 0)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            collected.append(data)
            if data.isEmpty || collected.hasValues(after: marker) { read.signal() }
        }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            NSLog("textier: couldn't run %@ to read $EDITOR: %@", shell, error.localizedDescription)
            return ShellEnvironment()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            NSLog("textier: %@ took too long to report $EDITOR; using the defaults", shell)
            process.terminate()
            return ShellEnvironment()
        }
        // Not read to the end: a job the rc files start in the background keeps the
        // pipe open, maybe for good. The values were printed before the shell
        // exited, so they're in the pipe; a moment is enough to gather them.
        _ = read.wait(timeout: .now() + .milliseconds(500))
        output.fileHandleForReading.readabilityHandler = nil
        let environment = parse(String(decoding: collected.data, as: UTF8.self))
        NSLog("textier: login shell $EDITOR is %@", environment.editor ?? "unset")
        return environment
    }

    private static func parse(_ output: String) -> ShellEnvironment {
        guard let start = output.range(of: marker, options: .backwards) else { return ShellEnvironment() }
        let values = output[start.upperBound...].split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        func value(_ index: Int) -> String? {
            guard values.indices.contains(index) else { return nil }
            let trimmed = values[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return ShellEnvironment(editor: value(0), path: value(1))
    }
}

/// Bytes gathered from a pipe on a background queue.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()

    var data: Data { lock.withLock { bytes } }

    func append(_ data: Data) {
        lock.withLock { bytes.append(data) }
    }

    /// Whether the bytes hold `marker` and the two NUL-terminated values after it.
    func hasValues(after marker: String) -> Bool {
        lock.withLock {
            guard let start = bytes.range(of: Data(marker.utf8), options: .backwards) else { return false }
            return bytes[start.upperBound...].count(where: { $0 == 0 }) >= 2
        }
    }
}
