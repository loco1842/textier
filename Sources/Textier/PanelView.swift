import AppKit
import SwiftUI
import TextierCore

/// The Panel's content: the header strip, then the Input beside the Inspector.
/// No footer and no dividers.
struct PanelView: View {
    let model: PanelModel
    let split: NSSplitView
    /// Where the header starts, past the window's traffic lights.
    var leadingInset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(model: model, leadingInset: leadingInset)
            SplitHost(split: split)
        }
        .frame(minWidth: 560, minHeight: 280)
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// The 52 pt strip that drags the window: the Highlighting and Wrap Lines toggles
/// and the Tabs/List switch as glass icon buttons, then "Inspecting…" while a large
/// Input is inspected, the color-bar summary and the warnings badge.
private struct PanelHeader: View {
    let model: PanelModel
    var leadingInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A button's tooltip, with its command's shortcut as the Config sets it.
    private func help(_ text: String, _ command: ShortcutCommand) -> String {
        AppConfig.store.config.shortcuts[command].map { "\(text) (\($0.symbols))" } ?? text
    }

    /// "⌘-click", as the Config's Match click modifiers make it.
    private var clickName: String {
        Shortcut.symbols(of: AppConfig.store.config.shortcuts.matchClick) + "-click"
    }

    var body: some View {
        HStack(spacing: 8) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    GlassButtonGroup {
                        GlassIconButton(
                            title: "Highlighting", systemImage: "highlighter", isOn: model.highlighting,
                            help: help("Tint Matches in the Input; \(clickName) one to inspect it", .toggleHighlighting)
                        ) { model.highlighting.toggle() }
                        GlassIconButton(
                            title: "Wrap Lines", systemImage: "arrow.turn.down.left", isOn: model.wrapsLines,
                            help: help("Wrap long lines in the Input, or scroll them sideways", .toggleWrapLines)
                        ) { model.wrapsLines.toggle() }
                    }
                    GlassButtonGroup {
                        GlassIconButton(
                            title: "Tabs", systemImage: "rectangle.topthird.inset.filled", isOn: model.layout == .tabs,
                            help: help("Tabs: one Pattern at a time", .switchInspectorLayout)
                        ) { model.layout = .tabs }
                        GlassIconButton(
                            title: "List", systemImage: "list.bullet.indent", isOn: model.layout == .list,
                            help: help("List: every Pattern in one collapsible list", .switchInspectorLayout)
                        ) { model.layout = .list }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Inspector layout")
                }
            }
            Spacer(minLength: 8)
            if let refusal = model.refusal {
                Label(refusal, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
            }
            if model.isInspecting {
                Text("Inspecting… \(model.inspectionPercent)%")
                    .monospacedDigit()
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            if model.inspection.showsInspector {
                MatchCounts(model: model)
                    .transition(.opacity)
            }
            if !model.warnings.isEmpty {
                WarningsBadge(warnings: model.warnings)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        // Each pass's counts and warnings settle in rather than snap.
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: model.inspection.showsInspector)
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: model.isInspecting)
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: model.refusal)
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: model.patternTabs.map(\.entries.count))
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: model.warnings)
        .padding(.leading, max(11, leadingInset))
        .padding(.trailing, 11)
        .frame(height: 52)
        .background(WindowDragArea())
    }
}

/// Glass icon buttons side by side in one capsule.
private struct GlassButtonGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(2)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// An icon button in a glass group; `isOn` fills it faintly.
private struct GlassIconButton: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 26)
                .foregroundStyle(isOn ? .primary : .secondary)
                .background(Capsule().fill(isOn ? Color.primary.opacity(0.1) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A color bar with a segment per Pattern, sized by its Match count, and
/// "N Patterns · M Matches".
private struct MatchCounts: View {
    let model: PanelModel

    var body: some View {
        let patterns = model.patternTabs
        let matches = model.matchCount
        HStack(spacing: 10) {
            GeometryReader { geometry in
                let gaps = CGFloat(max(0, patterns.count - 1)) * 1.5
                HStack(spacing: 1.5) {
                    ForEach(patterns) { tab in
                        Rectangle()
                            .fill(Color(model.color(of: tab), \.solid))
                            .frame(width: (geometry.size.width - gaps) * CGFloat(tab.entries.count) / CGFloat(max(1, matches)))
                    }
                }
            }
            .frame(width: 72, height: 6)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            Text(model.countLine)
                .contentTransition(.numericText(value: Double(matches)))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// "⚠ N", opening a popover that lists every warning in full.
struct WarningsBadge: View {
    let warnings: [String]
    @State private var isShowingList = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { isShowingList.toggle() } label: {
            Label {
                Text("\(warnings.count)")
                    .contentTransition(.numericText(value: Double(warnings.count)))
            } icon: {
                // The triangle bounces when the count changes.
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : warnings.count)
            }
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Warnings")
        .accessibilityLabel(counted(warnings.count, "warning"))
        .popover(isPresented: $isShowingList, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Warnings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(width: 340, alignment: .leading)
        }
    }
}

/// Drags the window from wherever it shows through, since the Panel has no title bar.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Embeds the Panel's split view (the Input and the Inspector), which the
/// controller owns.
private struct SplitHost: NSViewRepresentable {
    let split: NSSplitView

    func makeNSView(context: Context) -> NSSplitView { split }
    func updateNSView(_ nsView: NSSplitView, context: Context) {}
}
