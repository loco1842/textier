import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import TextierCore

/// The Config the app currently detects with. Everything that detects (the Panel,
/// Match Windows) reads it at detection time, so a reload takes effect on the next pass.
@MainActor
enum AppConfig {
    /// `TEXTIER_CONFIG` overrides the file's location, for trying configs out; the
    /// app tests replace the store with one on a temporary file.
    static var store = ConfigStore(
        fileURL: ProcessInfo.processInfo.environment["TEXTIER_CONFIG"].map { URL(fileURLWithPath: $0) }
            ?? ConfigFile.defaultLocation
    )

    static var current: Config { store.config }
}

/// Owns the config file: writes the defaults on first launch, loads it, watches it
/// and reloads on save, and writes Settings' changes. A file that can't be used
/// leaves the last good Config active.
@MainActor
@Observable
final class ConfigStore {
    let fileURL: URL
    private(set) var config = Config.default
    /// The entries the file has but `config` couldn't take, kept for writing back.
    @ObservationIgnored private var skipped = SkippedEntries()
    /// Every Grok Definition the file has, broken ones too: what loading checks
    /// Patterns against, so Settings can check them the same way.
    private(set) var grokAsWritten: [GrokDefinition] = []
    /// Problems found by the last load. A fatal one means `config` is the last good one.
    private(set) var loadWarnings: [ConfigWarning] = []
    /// Registers the Config's shortcut after every load; nil registers nothing.
    @ObservationIgnored var shortcutRegistrar: ShortcutRegistrar?
    /// Set after a load when the Config's shortcut couldn't be registered.
    private(set) var shortcutWarning: ConfigWarning?
    /// Set by `Editor` when the editor command failed and the file opened with the
    /// default app instead; cleared by the next editor launch that works, or a reload.
    var editorWarning: ConfigWarning? {
        didSet { if editorWarning != oldValue { onWarningsChange() } }
    }

    /// The syntax-coloring theme for each appearance: the bundled GitHub themes.
    let lightTheme = Theme.githubLight
    let darkTheme = Theme.githubDark

    /// Everything the footer and the menu bar badge should show.
    var warnings: [ConfigWarning] {
        loadWarnings + [shortcutWarning, editorWarning].compactMap { $0 }
    }

    /// Runs after every reload.
    @ObservationIgnored var onReload: () -> Void = {}
    /// Runs when a warning appears or clears between reloads.
    @ObservationIgnored var onWarningsChange: () -> Void = {}
    /// Posted after every load of the file, for views that come and go (Match Windows).
    static let didReload = Notification.Name("textier.ConfigStore.didReload")
    @ObservationIgnored private var watcher: FileWatcher?
    /// The bytes behind the last load, so watcher events that don't change the file are ignored.
    @ObservationIgnored private var loadedData: Data?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Writes the defaults if the file is absent, loads it and starts watching it.
    func start() {
        do {
            try ConfigFile.writeDefaultIfAbsent(at: fileURL)
        } catch {
            NSLog("textier: couldn't write the default config: %@", error.localizedDescription)
        }
        reload()
        watcher = FileWatcher(fileURL: fileURL) { [weak self] in self?.reload(onlyIfChanged: true) }
    }

    /// Reads the file again, as the watcher does after a save.
    func reload() {
        reload(onlyIfChanged: false)
    }

    /// Writes `config` to the file, as Settings does with every valid change, and
    /// loads it at once, so the Panel follows before the watcher notices. The watcher
    /// then finds the bytes it already loaded and does nothing. Entries the last
    /// load skipped are written back as they were, so a hand edit still being fixed
    /// isn't lost. A config file that's a symbolic link (into a dotfiles repo, say)
    /// stays one: the file it points to is written, resolved on each write in case
    /// the link came later.
    func write(_ config: Config) throws {
        let data = ConfigFile.encode(config, keeping: skipped)
        try data.write(to: fileURL.resolvingSymlinksInPath(), options: .atomic)
        load(data)
    }

    private func reload(onlyIfChanged: Bool) {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            loadedData = nil
            editorWarning = nil
            loadWarnings = [ConfigWarning(
                "Couldn't read \(fileURL.path) (\(error.localizedDescription)); keeping the last good config",
                isFatal: true
            )]
            registerShortcut()
            onReload()
            return
        }
        if onlyIfChanged, data == loadedData { return }
        load(data)
    }

    /// Loads the file's bytes: the Config and its warnings, then the appearance and
    /// the shortcut.
    private func load(_ data: Data) {
        loadedData = data
        editorWarning = nil

        let load = ConfigFile.load(data)
        if let config = load.config {
            self.config = config
            skipped = load.skipped
            grokAsWritten = config.grok + load.skipped.grok.compactMap { skipped in
                guard case .string(let regex) = skipped.entry.value, GrokDefinition.isValidName(skipped.entry.key)
                else { return nil }
                return GrokDefinition(name: skipped.entry.key, regex: regex)
            }
        }
        loadWarnings = load.warnings.map { warning in
            guard warning.isFatal else { return warning }
            return ConfigWarning(warning.message + "; keeping the last good config", isFatal: true)
        }
        NSLog("textier: loaded %@ (%ld patterns, %ld warnings)", fileURL.path, config.patterns.count, loadWarnings.count)
        for warning in loadWarnings { NSLog("textier: config warning: %@", warning.message) }
        applyAppearance()
        registerShortcut()
        onReload()
        NotificationCenter.default.post(name: Self.didReload, object: self)
    }
}

extension ConfigStore {
    fileprivate func registerShortcut() {
        guard let shortcutRegistrar else { return }
        shortcutWarning = shortcutRegistrar.register(config.shortcut)
    }

    /// Makes the whole app light, dark, or follow the system, per the Config.
    fileprivate func applyAppearance() {
        NSApplication.shared.appearance = switch config.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Keeps the global shortcut registered as the Config's `shortcut`. The app
/// registers through its `HotKey`; the app tests through a recorder.
@MainActor
final class ShortcutRegistrar {
    /// Registers a shortcut system-wide, replacing the previous one, and returns
    /// Carbon's status.
    private let registerSystemWide: (Shortcut) -> OSStatus
    /// The shortcut that's registered now, if any.
    private(set) var registered: Shortcut?

    init(register: @escaping (Shortcut) -> OSStatus) {
        registerSystemWide = register
    }

    /// Registers `shortcut` if it changed. If it can't be registered, the previous
    /// one is put back; returns the warning that says so, or nil when `shortcut` is
    /// the one registered.
    func register(_ shortcut: Shortcut) -> ConfigWarning? {
        if shortcut == registered { return nil }
        let status = registerSystemWide(shortcut)
        if status == noErr {
            registered = shortcut
            return nil
        }
        let reason = status == OSStatus(eventHotKeyExistsErr) ? "it's already taken" : "OSStatus \(status)"
        var message = "Couldn't register the shortcut \(shortcut) (\(reason))"
        if let previous = registered, registerSystemWide(previous) == noErr {
            message += "; still using \(previous)"
        } else {
            registered = nil
        }
        return ConfigWarning(message)
    }
}

/// Calls back (debounced, on the main thread) when a file changes, including when an
/// editor saves by writing a temporary file and renaming it over the original: the
/// directory is watched for that, and the file watch is re-armed after every change.
///
/// The events arrive on a queue of their own and reach the main thread through
/// its run loop, as the debounce's timer does, so both also come through while the
/// app tests hold the main queue.
@MainActor
private final class FileWatcher {
    private let fileURL: URL
    private let onChange: () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: Timer?
    private static let events = DispatchQueue(label: "textier.FileWatcher")

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        directorySource = watch(fileURL.deletingLastPathComponent().path, events: .write)
        fileSource = watch(fileURL.path, events: [.write, .extend, .delete, .rename])
    }

    private func watch(_ path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: Self.events)
        // @Sendable, so the handler isn't main-actor code: it runs on `events`, and
        // Swift traps a main-actor closure that runs anywhere but the main queue.
        source.setEventHandler { @Sendable [weak self] in
            RunLoop.main.perform { MainActor.assumeIsolated { self?.changed() } }
        }
        source.setCancelHandler { @Sendable in close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settled() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pending = timer
    }

    /// A moment after the last event: the save is done.
    private func settled() {
        pending = nil
        // The save may have replaced the file, leaving the old watch on a deleted inode.
        fileSource?.cancel()
        fileSource = watch(fileURL.path, events: [.write, .extend, .delete, .rename])
        onChange()
    }

    isolated deinit {
        pending?.invalidate()
        directorySource?.cancel()
        fileSource?.cancel()
    }
}
