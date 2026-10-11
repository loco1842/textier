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
            LabeledContent("Shortcut") {
                ShortcutRecorder(shortcut: model.config.shortcut, draft: model.draft(.shortcut)) {
                    model.recordShortcut(modifiers: $0, key: $1)
                }
            }
            if let draft = model.draft(.shortcut) {
                DraftNote(draft: draft, fileValue: model.config.shortcut.symbols) { model.discardDraft(.shortcut) }
            }
            Picker("Clear the selection", selection: Binding(
                get: { model.config.clearSelectionAfter }, set: { model.setClearSelectionAfter($0) }
            )) {
                ForEach(model.clearSelectionChoices, id: \.self) { seconds in
                    Text(SettingsModel.clearSelectionTitle(seconds)).tag(seconds)
                }
            }
        } footer: {
            Text("Opens the selected text from any app in the menu bar popover. It keeps the selection for the menu bar icon until the next one, or clears it this long after it closes.")
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
            Picker("A click on JSON copies", selection: Binding(get: { model.config.copyJSON }, set: { model.setCopyJSON($0) })) {
                Text("Raw").tag(CopyJSON.raw)
                Text("Beautified").tag(CopyJSON.pretty)
            }
            Picker("Inspector layout", selection: Binding(
                get: { model.config.inspectorLayout }, set: { model.setInspectorLayout($0) }
            )) {
                Text("Tabs").tag(InspectorLayout.tabs)
                Text("List").tag(InspectorLayout.list)
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
    let shortcut: Shortcut
    let draft: SettingsModel.Draft?
    let record: (Shortcut.Modifiers, String) -> Void
    @State private var monitor: Any?
    /// What ends the recording besides a key press: the window resigning key or
    /// closing, and the app resigning active.
    @State private var observers: [NSObjectProtocol] = []

    var body: some View {
        Button(action: { monitor == nil ? start() : stop() }) {
            Text(monitor != nil ? "Type the shortcut…" : draft?.text ?? shortcut.symbols)
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
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        record(modifiers, Self.keyName(event))
    }

    /// The `Shortcut` key name for the physical key, or what the key types when a
    /// Shortcut can't use it.
    private static func keyName(_ event: NSEvent) -> String {
        if let name = keyNames[Int(event.keyCode)] { return name }
        let typed = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isFunctionKey = typed.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) }
        return typed.isEmpty || isFunctionKey ? "key \(event.keyCode)" : typed
    }

    /// The keys a Shortcut accepts (`Shortcut.keys`), by virtual key code, and a few
    /// common ones it doesn't, by symbol.
    private static let keyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e",
            kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j",
            kVK_ANSI_K: "k", kVK_ANSI_L: "l", kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o",
            kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
            kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x", kVK_ANSI_Y: "y",
            kVK_ANSI_Z: "z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "space",
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (index, code) in functionKeys.enumerated() { names[code] = "f\(index + 1)" }
        return names
    }()
}

// MARK: Appearance

private struct AppearanceSettings: View {
    let model: SettingsModel

    var body: some View {
        Section {
            Picker("Appearance", selection: Binding(get: { model.config.appearance }, set: model.setAppearance)) {
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
