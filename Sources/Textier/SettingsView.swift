import AppKit
import Carbon.HIToolbox
import SwiftUI
import TextierCore
import UniformTypeIdentifiers

/// Settings' content: the sections in a sidebar, the selected one on the right
/// with its warnings on top.
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        NavigationSplitView {
            List(SettingsModel.Section.allCases, selection: selection) { section in
                Label(section.title, systemImage: section.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.section.title)
                    .font(.title2.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                if model.section == .patterns {
                    // A list beside an editor, which a Form can't hold.
                    PatternsSettings(model: model)
                } else {
                    Form {
                        SectionWarnings(model: model)
                        switch model.section {
                        case .general: GeneralSettings(model: model)
                        case .shortcuts: ShortcutsSettings(model: model)
                        case .appearance: AppearanceSettings(model: model)
                        case .grokDefinitions: GrokSettings(model: model)
                        case .patterns: EmptyView()
                        }
                    }
                    .formStyle(.grouped)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 400)
    }

    /// The sidebar's selection; a List selects through an optional.
    private var selection: Binding<SettingsModel.Section?> {
        Binding(get: { model.section }, set: { if let section = $0 { model.section = section } })
    }
}

/// The selected section's warnings, and why the last edit wasn't written, with a
/// way to the config file to fix them at their cause.
struct SectionWarnings: View {
    let model: SettingsModel

    var body: some View {
        let messages = model.sectionMessages
        if !messages.isEmpty {
            Section {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                Button("Open Config File") { model.openConfigFile() }
                    .buttonStyle(.link)
            }
        }
    }
}

// MARK: General

private struct GeneralSettings: View {
    let model: SettingsModel
    @State private var editorCommand = ""

    var body: some View {
        Section {
            Picker("Clear the selection", selection: Binding(
                get: { model.config.clearSelectionAfter }, set: { model.setClearSelectionAfter($0) }
            )) {
                ForEach(model.clearSelectionChoices, id: \.self) { seconds in
                    Text(SettingsModel.clearSelectionTitle(seconds)).tag(seconds)
                }
            }
        } footer: {
            Text("The Selection Popover keeps the selection for its icon until the next one, or clears it this long after it closes.")
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { model.config.checkForUpdates }, set: { model.setCheckForUpdates($0) }
            ))
            LabeledContent("textier \(Updater.shared.current?.description ?? "(development build)")") {
                Button("Check Now") { Updater.shared.check(userInitiated: true) }
            }
        } footer: {
            Text("Looks for a newer release on GitHub at launch and once a day; that's all textier sends over the network.")
                .foregroundStyle(.secondary)
        }
        Section {
            LabeledContent("Editor command") {
                HStack {
                    CommitField(text: $editorCommand, value: model.config.editorCommand ?? "", prompt: "$EDITOR") {
                        model.setEditorCommand($0)
                    }
                    Button("Test") {
                        model.setEditorCommand(editorCommand)
                        model.testEditorCommand()
                    }
                    .help("Open the config file with this command")
                }
            }
        } footer: {
            Text("Open in Editor runs this, with {path} and {line} filled in. Empty uses $EDITOR, or Cursor.")
                .foregroundStyle(.secondary)
        }
        Section {
            Picker("Inspector layout", selection: Binding(
                get: { model.config.inspectorLayout }, set: { model.setInspectorLayout($0) }
            )) {
                Text("Tabs").tag(InspectorLayout.tabs)
                Text("List").tag(InspectorLayout.list)
            }
        }
    }
}

// MARK: Shortcuts

/// The global shortcut, then each command's in the app with its own recorder (and
/// buttons for none and its default), then the modifiers that select tabs and
/// Matches.
private struct ShortcutsSettings: View {
    let model: SettingsModel

    var body: some View {
        Section {
            LabeledContent("Open the Selection Popover") {
                ShortcutRecorder(shortcut: model.config.shortcut, draft: model.draft(.shortcut)) {
                    model.recordShortcut(modifiers: $0, key: $1)
                }
            }
            if let draft = model.draft(.shortcut) {
                DraftNote(draft: draft, fileValue: model.config.shortcut.symbolText) { model.discardDraft(.shortcut) }
            }
        } footer: {
            Text("Works in any app: opens the selected text in the Selection Popover.")
                .foregroundStyle(.secondary)
        }
        Section("In textier") {
            ForEach(ShortcutCommand.allCases, id: \.self) { command in
                commandRow(command)
            }
        }
        Section {
            Picker("Select tab 1–9", selection: Binding(
                get: { model.config.shortcuts.selectTab }, set: { model.setSelectTabModifiers($0) }
            )) {
                ForEach(model.selectTabChoices(), id: \.rawValue) { modifiers in
                    Text(Shortcut.symbols(of: modifiers) + "1–9").tag(modifiers)
                }
            }
            Picker("Select a Match in the text", selection: Binding(
                get: { model.config.shortcuts.matchClick }, set: { model.setMatchClickModifiers($0) }
            )) {
                ForEach(model.modifierChoices(including: model.config.shortcuts.matchClick), id: \.rawValue) { modifiers in
                    Text(Shortcut.symbols(of: modifiers) + "-click").tag(modifiers)
                }
            }
        } footer: {
            HStack {
                Text("A plain click in the text places the cursor.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { model.restoreDefaultShortcuts() }
            }
        }
    }

    @ViewBuilder private func commandRow(_ command: ShortcutCommand) -> some View {
        let shortcut = model.config.shortcuts[command]
        LabeledContent(command.title) {
            HStack(spacing: 4) {
                ShortcutRecorder(shortcut: shortcut, draft: model.draft(.commandShortcut(command))) {
                    model.recordShortcut(for: command, modifiers: $0, key: $1)
                }
                Button { model.clearShortcut(of: command) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .disabled(shortcut == nil)
                    .help("No shortcut")
                    .accessibilityLabel("No shortcut for \(command.title)")
                Button { model.resetShortcut(of: command) } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .disabled(shortcut == command.defaultShortcut)
                    .help("Back to \(command.defaultShortcut?.symbolText ?? "none")")
                    .accessibilityLabel("Default shortcut for \(command.title)")
            }
        }
        if let draft = model.draft(.commandShortcut(command)) {
            DraftNote(draft: draft, fileValue: shortcut?.symbolText ?? "none") {
                model.discardDraft(.commandShortcut(command))
            }
        }
    }
}

/// Under a field holding a draft: why it can't be saved, a note when the file
/// changed meanwhile, and a way back to the file's value.
struct DraftNote: View {
    let draft: SettingsModel.Draft
    let fileValue: String
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(draft.problem, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
            if draft.fileChanged {
                Label("The config file changed while you were editing; it now has \(fileValue).", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            }
            Button("Use \(fileValue)", action: discard)
                .buttonStyle(.link)
        }
        .font(.callout)
    }
}

/// A button that records the next key press in the Settings window as the
/// shortcut. Esc cancels, and so does the window losing the keyboard, so a key
/// pressed in the Panel or another app is never taken for it.
private struct ShortcutRecorder: View {
    /// The shortcut as the file has it; nil for none.
    let shortcut: Shortcut?
    let draft: SettingsModel.Draft?
    let record: (Shortcut.Modifiers, String) -> Void
    @State private var monitor: Any?
    /// What ends the recording besides a key press: the window resigning key or
    /// closing, and the app resigning active.
    @State private var observers: [NSObjectProtocol] = []

    var body: some View {
        Button(action: { monitor == nil ? start() : stop() }) {
            Text(monitor != nil ? "Type the shortcut…" : draft?.text ?? shortcut?.symbolText ?? "None")
                .frame(minWidth: 120)
        }
        .help("Click, then press the shortcut")
        .onDisappear(perform: stop)
    }

    private func start() {
        guard let window = SettingsWindowController.current?.window else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let inWindow = MainActor.assumeIsolated { event.window === window }
            guard inWindow else { return event }
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
        let names: [(Notification.Name, AnyObject?)] = [
            (NSWindow.didResignKeyNotification, window),
            (NSWindow.willCloseNotification, window),
            (NSApplication.didResignActiveNotification, nil),
        ]
        observers = names.map { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { _ in
                MainActor.assumeIsolated { stop() }
            }
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        defer { stop() }
        if Int(event.keyCode) == kVK_Escape, flags.isDisjoint(with: [.control, .option, .command, .shift]) { return }
        record(ShortcutKeys.modifiers(flags), Self.keyName(event))
    }

    /// The `Shortcut` key name for the physical key, or what the key types when a
    /// Shortcut can't use it.
    static func keyName(_ event: NSEvent) -> String {
        if let name = ShortcutKeys.keyName(event) { return name }
        if let symbol = otherKeys[Int(event.keyCode)] { return symbol }
        let typed = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isFunctionKey = typed.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) }
        return typed.isEmpty || isFunctionKey ? "key \(event.keyCode)" : typed
    }

    /// A few common keys a Shortcut doesn't take, by symbol.
    private static let otherKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]
}

// MARK: Appearance

private struct AppearanceSettings: View {
    let model: SettingsModel

    var body: some View {
        Section {
            Picker("Appearance", selection: Binding(get: { model.config.appearance }, set: { model.setAppearance($0) })) {
                Text("System").tag(AppearanceSetting.system)
                Text("Light").tag(AppearanceSetting.light)
                Text("Dark").tag(AppearanceSetting.dark)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("The Panel, Match Windows and Settings follow it, and the JSON Viewer colors with GitHub Light or Dark to match.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: Fields

/// A text field that writes its text when Return is pressed or it loses focus,
/// rather than on every keystroke, and shows the file's value whenever that changes.
struct CommitField: View {
    @Binding var text: String
    let value: String
    let prompt: String
    var monospaced = false
    let commit: (String) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt))
            .font(monospaced ? .system(.body, design: .monospaced) : nil)
            .multilineTextAlignment(.leading)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 200)
            .focused($isFocused)
            .onSubmit(save)
            .onChange(of: isFocused) { if !isFocused { save() } }
            .onChange(of: value, initial: true) { text = value }
    }

    private func save() {
        if text != value { commit(text) }
    }
}
