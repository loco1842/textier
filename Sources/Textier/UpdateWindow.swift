import AppKit
import SwiftUI
import TextierCore

/// The update window: what a check found, and the offer to install it.
@MainActor
enum UpdateWindow {
    private static var window: NSWindow?

    static func show(activating: Bool = true) {
        let present = activating ? Effects.present : Effects.presentInBackground
        if let window {
            present(window)
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
        present(window)
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
        Text(updater.installProblem
            ?? "After it relaunches, macOS asks for Accessibility again: textier isn't signed with a Developer ID.")
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
