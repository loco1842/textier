import SwiftUI
import TextierCore

/// The Grok Definitions section, as Form sections: the user's own definitions
/// (editable, with a way to add and to paste `NAME regex` lines), then the
/// bundled library to browse. Any definition can start a new Pattern.
struct GrokSettings: View {
    @Bindable var model: SettingsModel
    @State private var newName = ""
    @State private var newRegex = ""
    @State private var addProblem: String?
    @State private var pasted = ""
    @State private var pasteProblems: [String] = []
    @State private var deleteProblem: (name: String, problem: String)?

    var body: some View {
        Section {
            TextField("Filter", text: $model.grokFilter, prompt: Text("Filter by name"))
        } footer: {
            Text("Use one in a Pattern's regex as %{NAME}, or %{NAME:field} to show what it matched as a Field.")
                .foregroundStyle(.secondary)
        }
        yours
        paste
        bundled
    }

    private var yours: some View {
        Section("Yours") {
            ForEach(model.visibleUserGrok, id: \.name) { definition in
                UserGrokRow(model: model, definition: definition) {
                    if let problem = model.deleteGrokDefinition(named: definition.name) {
                        deleteProblem = (definition.name, problem)
                    }
                }
                if let deleteProblem, deleteProblem.name == definition.name {
                    Label("Can't delete \(deleteProblem.name): \(deleteProblem.problem)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            HStack {
                TextField("Name", text: $newName, prompt: Text("NAME"))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 150)
                TextField("Regex", text: $newRegex, prompt: Text("regex"))
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newName.isEmpty || newRegex.isEmpty)
            }
            .labelsHidden()
            if let addProblem {
                Label(addProblem, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    private var paste: some View {
        Section {
            TextEditor(text: $pasted)
                .font(.system(.callout, design: .monospaced))
                .frame(height: 70)
            HStack {
                Spacer()
                Button("Add Lines") {
                    pasteProblems = model.pasteGrokDefinitions(pasted)
                    if pasteProblems.isEmpty { pasted = "" }
                }
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(pasteProblems, id: \.self) { problem in
                Label(problem, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        } header: {
            Text("Paste from Logstash or StreamSets")
        } footer: {
            Text("One NAME regex per line; # comments and blank lines are skipped.")
                .foregroundStyle(.secondary)
        }
    }

    private var bundled: some View {
        Section("Bundled") {
            ForEach(model.visibleBundledGrok, id: \.name) { definition in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(definition.name).font(.system(.body, design: .monospaced).bold())
                            if model.config.grok.contains(where: { $0.name == definition.name }) {
                                Text("overridden").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(definition.regex)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                            .help(definition.regex)
                    }
                    Spacer()
                    Button("New Pattern") { model.newPattern(fromGrok: definition.name) }
                        .help("Add a Pattern named after it, matching %{\(definition.name)}")
                }
            }
        }
    }

    private func add() {
        addProblem = model.addGrokDefinition(name: newName, regex: newRegex)
        if addProblem == nil {
            newName = ""
            newRegex = ""
        }
    }
}

/// One of the user's definitions: its name (marked when it overrides a bundled
/// one), its regex, saved as it's committed, and its error while it's a draft.
private struct UserGrokRow: View {
    let model: SettingsModel
    let definition: GrokDefinition
    let delete: () -> Void
    @State private var regex = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(definition.name).font(.system(.body, design: .monospaced).bold())
                if model.overridesBundled(definition.name) {
                    Text("overrides bundled")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
                Spacer()
                Button("New Pattern") { model.newPattern(fromGrok: definition.name) }
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete \(definition.name)")
            }
            CommitField(text: $regex, value: model.grokRegexText(named: definition.name), prompt: "regex", monospaced: true) {
                model.setGrokRegex($0, named: definition.name)
            }
            if let draft = model.draft(.grokRegex(definition.name)) {
                DraftNote(draft: draft, fileValue: definition.regex) { model.discardDraft(.grokRegex(definition.name)) }
            }
        }
    }
}
