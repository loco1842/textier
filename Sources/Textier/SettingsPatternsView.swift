import AppKit
import SwiftUI
import TextierCore

/// The Patterns section: the list in priority order beside the selected
/// Pattern's editor, with the section's warnings above.
struct PatternsSettings: View {
    let model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            WarningBanner(model: model)
            HStack(spacing: 0) {
                PatternList(model: model)
                    .frame(width: 270)
                Divider()
                if let index = model.selectedPattern, model.config.patterns.indices.contains(index) {
                    PatternEditor(model: model, index: index)
                        .id(index)
                } else {
                    Text("Select a Pattern to edit it")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

/// The section's warnings outside a Form: one line each, and the way to the file.
private struct WarningBanner: View {
    let model: SettingsModel

    var body: some View {
        let messages = model.sectionMessages
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                Button("Open Config File") { model.openConfigFile() }
                    .buttonStyle(.link)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            Divider()
        }
    }
}

// MARK: The list

/// Every Pattern in priority order, filtered, with a switch each; drag to reorder
/// while the filter is empty.
private struct PatternList: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter", text: $model.patternFilter, prompt: Text("Filter by name or regex"))
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List(selection: selection) {
                ForEach(model.visiblePatterns, id: \.self) { index in
                    PatternRow(model: model, index: index).tag(index)
                }
                .onMove(perform: model.patternFilter.isEmpty ? { model.movePatterns(from: $0, to: $1) } : nil)
            }
            Divider()
            HStack(spacing: 2) {
                Button { model.addPattern() } label: { Image(systemName: "plus") }
                    .help("Add a Pattern")
                Button { model.selectedPattern.map(model.deletePattern) } label: { Image(systemName: "minus") }
                    .help("Delete the selected Pattern")
                    .disabled(model.selectedPattern.map {
                        !model.config.patterns.indices.contains($0) || model.kind(ofPatternAt: $0) != .user
                    } ?? true)
                Spacer()
                Text("Earlier wins an overlap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    /// A click in the list saves the regex being typed before the editor changes
    /// Pattern, as leaving the field would; a click doesn't take the focus.
    private var selection: Binding<Int?> {
        Binding(get: { model.selectedPattern }, set: { model.commitEditedRegex(); model.selectedPattern = $0 })
    }
}

/// A Pattern's name, its name's color and its regex, with its on/off switch.
private struct PatternRow: View {
    let model: SettingsModel
    let index: Int

    var body: some View {
        // A row (and the editor below) can be drawn once more after its Pattern is
        // deleted, before the list catches up: then it draws nothing.
        if model.config.patterns.indices.contains(index) {
            row(model.config.patterns[index])
        }
    }

    private func row(_ pattern: TextierCore.Pattern) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(model.color(ofPatternAt: index), \.solid))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(pattern.name)
                Text(subtitle(pattern))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Toggle("On", isOn: Binding(get: { pattern.enabled }, set: { model.setPatternEnabled($0, at: index) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .help(subtitle(pattern))
    }

    private func subtitle(_ pattern: TextierCore.Pattern) -> String {
        pattern.regex ?? "Built-in"
    }
}

// MARK: The editor

/// The selected Pattern: name, regex with its error and test box, Actions and
/// color. A Built-in Pattern only says what it is.
private struct PatternEditor: View {
    @Bindable var model: SettingsModel
    let index: Int
    @State private var name = ""
    @FocusState private var regexFocused: Bool

    var body: some View {
        if model.config.patterns.indices.contains(index) {
            form(model.config.patterns[index])
        }
    }

    private func form(_ pattern: TextierCore.Pattern) -> some View {
        let kind = model.kind(ofPatternAt: index)
        return Form {
            if kind == .builtin {
                Section {
                    LabeledContent("Name", value: pattern.name)
                } footer: {
                    Text("A Built-in Pattern: code detects it, so it can only be turned on and off.")
                        .foregroundStyle(.secondary)
                }
            } else {
                nameSection
                regexSection
                actionsSection(pattern)
                colorSection(pattern)
                Section {
                    HStack {
                        Button("Duplicate") { model.duplicatePattern(at: index) }
                        if model.canRestoreDefault(at: index) {
                            Button("Restore Default") { model.restoreDefault(at: index) }
                        }
                        Spacer()
                        if kind == .user {
                            Button("Delete", role: .destructive) { model.deletePattern(at: index) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var nameSection: some View {
        Section {
            LabeledContent("Name") {
                CommitField(text: $name, value: model.nameText(at: index), prompt: "What it detects") {
                    model.setPatternName($0, at: index)
                }
            }
            if let draft = model.draft(.patternName(index)) {
                DraftNote(draft: draft, fileValue: model.config.patterns[index].name) {
                    model.discardDraft(.patternName(index))
                }
            }
        } footer: {
            Text("Patterns that share a name share one Inspector group and color.")
                .foregroundStyle(.secondary)
        }
    }

    /// The regex as typed, its compile error, and the test box running it.
    private var regexSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Regex")
                TextField("", text: regexText, prompt: Text(#"Perl-style; %{NAME} for grok"#), axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1...6)
                    .focused($regexFocused)
                    .onSubmit { model.commitEditedRegex() }
                    .onChange(of: regexFocused) { if !regexFocused { model.commitEditedRegex() } }
                if case .failure(let error) = model.testMatches {
                    Label(error.message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else if let draft = model.draft(.patternRegex(index)) {
                    // A draft that compiles is one the config file couldn't take.
                    Text(model.compiles(draft.text) ? "Not saved: \(draft.problem)" : "Not saved until it compiles.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            TestBoxSection(model: model, color: model.color(ofPatternAt: index))
        } footer: {
            Text("Saved on Return or when you leave the field. The test box runs it as you type.")
                .foregroundStyle(.secondary)
        }
    }

    private var regexText: Binding<String> {
        Binding(get: { model.editedRegex ?? model.regexText(at: index) }, set: { model.editedRegex = $0 })
    }

    private func actionsSection(_ pattern: TextierCore.Pattern) -> some View {
        Section {
            ForEach(Action.allCases, id: \.self) { action in
                Toggle(action.title, isOn: Binding(
                    get: { pattern.actions.contains(action) },
                    set: { model.setPatternAction(action, on: $0, at: index) }
                ))
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("The first is what Return or a double-click in the Inspector runs: \(pattern.actions.first?.title ?? "none").")
                .foregroundStyle(.secondary)
        }
    }

    private func colorSection(_ pattern: TextierCore.Pattern) -> some View {
        let color = model.color(ofPatternAt: index)
        let isFirstOfName = model.config.patterns.firstIndex { $0.name == pattern.name } == index
        return Section {
            ColorPicker("Light appearance", selection: colorBinding(\.light, of: color), supportsOpacity: true)
            ColorPicker("Dark appearance", selection: colorBinding(\.dark, of: color), supportsOpacity: true)
            if pattern.color != nil {
                Button("Use the Default Color") { model.setPatternColor(nil, at: index) }
            }
        } header: {
            Text("Color")
        } footer: {
            if !isFirstOfName {
                Text("The first Pattern named “\(pattern.name)” sets this name's color.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func colorBinding(_ half: WritableKeyPath<PatternColor, String>, of color: PatternColor) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: color[keyPath: half]) ?? .systemBlue) },
            set: { picked in
                var updated = color
                updated[keyPath: half] = NSColor(picked).hexString
                model.setPatternColor(updated, at: index)
            }
        )
    }
}

// MARK: The test box

/// Sample text, the Panel's Input to start with, with the regex's Matches
/// highlighted as it's typed; clicking in a Match shows its Fields.
private struct TestBoxSection: View {
    let model: SettingsModel
    let color: PatternColor

    var body: some View {
        let matches = (try? model.testMatches.get()) ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Test")
                Spacer()
                Text(matches.count == 1 ? "1 Match" : "\(matches.count) Matches")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            TestTextView(model: model, matches: matches, color: color)
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
            let fields = model.selectedTestFields
            if !fields.isEmpty {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(field.label)
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .trailing)
                        Text(field.value)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .font(.callout)
                }
            } else if !matches.isEmpty, matches.contains(where: { !$0.fields.isEmpty }) {
                Text("Click a Match to see its Fields.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }
}

/// The test box's editable text, tinted where the regex matches. A ⌘C in it is
/// textier's own copy (`OwnCopyTextView`).
private struct TestTextView: NSViewRepresentable {
    let model: SettingsModel
    let matches: [Match]
    let color: PatternColor

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = OwnCopyTextView(usingTextLayoutManager: false)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = model.testInput
        textView.delegate = context.coordinator
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, let storage = textView.textStorage else { return }
        if textView.string != model.testInput { textView.string = model.testInput }
        // A caret move redraws with the same text and Matches: the tint stands. A
        // typed character takes the tint next to it, so new text is tinted afresh.
        let tint = Coordinator.Tint(text: model.testInput, ranges: matches.map(\.range), color: color)
        guard tint != context.coordinator.lastTint else { return }
        context.coordinator.lastTint = tint
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: whole)
        for match in matches where NSMaxRange(match.range) <= storage.length {
            storage.addAttribute(.backgroundColor, value: NSColor(patternColor: color, role: \.tint), range: match.range)
        }
        storage.endEditing()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        /// What the text view was last tinted for.
        struct Tint: Equatable {
            var text: String
            var ranges: [NSRange]
            var color: PatternColor
        }

        let model: SettingsModel
        var lastTint: Tint?

        init(model: SettingsModel) {
            self.model = model
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            model.testInput = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            model.selectTestMatch(at: textView.selectedRange().location)
        }
    }
}
