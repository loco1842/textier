import AppKit
import SwiftUI
import TextierCore

/// The Inspector: a pane inset in the Panel, holding the Matches grouped by
/// Pattern (and Plain Text), as one pill tab per group or as one list with a
/// collapsible section per group (`inspectorLayout`), then the selected entry's
/// Action bar and its parsed view in a card. The row list and the card resize
/// against each other with an invisible divider.
struct InspectorView: View {
    let model: PanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The detail's opacity: dipped and brought back up when the selection changes.
    @State private var detailOpacity = 1.0
    /// The row list's height once the divider has been dragged; nil before.
    @State private var listHeight: CGFloat?

    var body: some View {
        let shown = model.inspection.showsInspector
        VStack(spacing: 0) {
            if model.layout == .tabs {
                TabBar(model: model)
            }
            ResizableSplit(topHeight: $listHeight, idealTop: fittedListHeight) {
                list
            } bottom: {
                detail
            }
        }
        .background(PaneBackground())
        .padding(.trailing, 8)
        .padding(.bottom, 8)
        // The pane slides and fades in when the Input gets its first Match.
        .opacity(shown ? 1 : 0)
        .offset(x: shown ? 0 : 14)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: shown)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                switch model.layout {
                case .tabs:
                    if let tab = model.selectedTab { rows(of: tab) }
                case .list:
                    // Headers are plain rows, not Section headers, which a plain list
                    // pins to its top on a bar.
                    ForEach(model.inspection.tabs) { tab in
                        SectionHeader(tab: tab, color: model.color(of: tab), isExpanded: expansion(of: tab.id))
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                            .selectionDisabled()
                        if !model.isCollapsed(tab.id) { rows(of: tab) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // No menu: the primary action is a double-click or Return on a row.
            .contextMenu(forSelectionType: EntryID.self, menu: { _ in }, primaryAction: { _ in model.runFirstAction() })
            .onKeyPress(phases: .down) { press in
                // Tab and Shift-Tab (a backtab character) go back to the Input.
                guard press.key == .tab || press.characters == "\u{19}" else { return .ignored }
                model.focusInput()
                return .handled
            }
            .onChange(of: model.inspection.selection) { _, selection in
                if let selection { proxy.scrollTo(selection) }
            }
        }
        .mask(EdgeFade(bottom: 12))
    }

    private func rows(of tab: InspectorTab) -> some View {
        ForEach(tab.entries, id: \.index) { entry in
            let id = EntryID(tab: tab.id, index: entry.index)
            let isSelected = model.inspection.selection == id
            EntryRow(
                entry: entry, color: entry.color ?? model.color(of: tab), parentColor: entry.parent.map(model.color(ofParent:)),
                isSelected: isSelected, readsAsUTC: model.readsDatetimeAsUTC
            )
            .tag(id)
            .id(id)
            .background(NoSystemHighlight())
            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(entry.color ?? model.color(of: tab), \.tint) : .clear)
                    // Keyboard focus: a ring in the solid color, as the Input rings the selection.
                    .strokeBorder(
                        isSelected && model.listHasFocus ? Color(entry.color ?? model.color(of: tab), \.solid) : .clear,
                        lineWidth: 1.5
                    )
                    .padding(.horizontal, 8)
            )
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: model.inspection.selection)
    }

    /// The row list's height before the divider is dragged: its rows', up to a cap,
    /// so the Action bar and card follow right under them.
    private var fittedListHeight: CGFloat {
        func height(of tab: InspectorTab) -> CGFloat {
            tab.entries.reduce(0) { $0 + ($1.summary == nil ? EntryRow.oneLineHeight : EntryRow.twoLineHeight) }
        }
        let rows: CGFloat = switch model.layout {
        case .tabs:
            model.selectedTab.map(height(of:)) ?? 0
        case .list:
            model.inspection.tabs.reduce(0) { total, tab in
                total + SectionHeader.height + (model.isCollapsed(tab.id) ? 0 : height(of: tab))
            }
        }
        return min(model.layout == .tabs ? 206 : 290, rows + 4)
    }

    private var selection: Binding<EntryID?> {
        Binding(
            get: { model.inspection.selection },
            set: { id in
                if let id { model.select(id) }
            }
        )
    }

    private func expansion(of id: InspectorTab.ID) -> Binding<Bool> {
        Binding(get: { !model.isCollapsed(id) }, set: { model.setCollapsed(id, !$0) })
    }

    @ViewBuilder private var detail: some View {
        @Bindable var model = model
        if let entry = model.selectedEntry {
            VStack(spacing: 0) {
                ActionBar(
                    items: entry.barItems(isPlainText: model.isPlainTextSelected, inMatchWindow: false),
                    color: model.selectedTab.map(model.color(of:)) ?? Palette.plainText
                ) {
                    model.run($0, on: entry)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                EntryDetailView(
                    entry: entry, readsAsUTC: $model.readsDatetimeAsUTC,
                    accent: model.selectedTab.map(model.color(of:)) ?? Palette.plainText
                )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
            // Another entry's card fades up from faint. Only the new card is ever
            // there: a crossfade would keep the old one (and its views) a moment.
            .opacity(detailOpacity)
            .onChange(of: model.inspection.selection) {
                guard !reduceMotion else { return }
                detailOpacity = 0.35
                RunLoop.main.perform {
                    MainActor.assumeIsolated {
                        withAnimation(.easeOut(duration: 0.15)) { detailOpacity = 1 }
                    }
                }
            }

        } else {
            Color.clear
        }
    }
}

/// The Inspector pane's fill: the window's material one step lighter, rounded to
/// nest in the window's corners, with a soft shadow, as mockup E draws it.
private struct PaneBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(nsColor: NSColor(
                light: NSColor.white.withAlphaComponent(0.5), dark: NSColor.white.withAlphaComponent(0.06)
            )))
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            .shadow(color: .black.opacity(0.12), radius: 15, y: 10)
    }
}

/// Two views stacked, resizable against each other by dragging the 8 pt gap
/// between them, which draws nothing.
private struct ResizableSplit<Top: View, Bottom: View>: View {
    @Binding var topHeight: CGFloat?
    let idealTop: CGFloat
    @ViewBuilder let top: Top
    @ViewBuilder let bottom: Bottom
    @State private var dragStart: CGFloat?

    private let minTop: CGFloat = 40
    private let minBottom: CGFloat = 160
    private let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.height - gap
            let height = clamped(topHeight ?? idealTop, in: available)
            VStack(spacing: 0) {
                top.frame(height: height)
                Color.clear
                    .frame(height: gap)
                    .contentShape(Rectangle())
                    .pointerStyle(.rowResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = dragStart ?? height
                                dragStart = start
                                topHeight = clamped(start + drag.translation.height, in: available)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                    .accessibilityHidden(true)
                bottom.frame(maxHeight: .infinity)
            }
        }
    }

    private func clamped(_ height: CGFloat, in available: CGFloat) -> CGFloat {
        max(min(minTop, available), min(height, available - minBottom))
    }
}

/// An opacity mask that fades its content out at the top and bottom edges.
struct EdgeFade: View {
    var top: CGFloat = 0
    var bottom: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: top)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: bottom)
        }
    }
}

/// The tab strip: a pill per tab, scrolling sideways when they overflow.
private struct TabBar: View {
    let model: PanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The selected tab's solid capsule slides from tab to tab.
    @Namespace private var selection
    /// The tab a dragged tab is over, which shows where it will go.
    @State private var dropTarget: InspectorTab.ID?
    /// The tab being dragged.
    @State private var dragged: InspectorTab.ID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(model.inspection.tabs.enumerated()), id: \.element.id) { number, tab in
                    let pill = TabPill(
                        tab: tab, color: model.color(of: tab), isSelected: model.selectedTab?.id == tab.id,
                        selection: selection
                    ) {
                        model.selectTab(tab.id)
                    }
                    .help((number < 9 ? "\(tab.title) (⌘\(number + 1))" : tab.title) + (tab.id == .plainText ? "" : " — drag to move"))
                    if tab.id == .plainText {
                        pill
                    } else {
                        // Plain Text stays last.
                        pill.modifier(TabDragging(model: model, tab: tab, dragged: $dragged, dropTarget: $dropTarget))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: model.selectedTab?.id)
    }
}

/// Dragging a Pattern's tab (or the Selection Popover's chip) onto another puts it
/// in that one's place (`moveTab`), an order every Inspector remembers. While
/// dragging, a bar in the target's color shows where it will land.
struct TabDragging: ViewModifier {
    let model: PanelModel
    let tab: InspectorTab
    @Binding var dragged: InspectorTab.ID?
    @Binding var dropTarget: InspectorTab.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onDrag {
                dragged = tab.id
                return NSItemProvider(object: tab.title as NSString)
            }
            .dropDestination(for: String.self) { names, _ in
                guard let name = names.first, name != tab.title,
                      let index = model.patternTabs.firstIndex(where: { $0.id == tab.id })
                else { return false }
                withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                    model.moveTab(named: name, to: index)
                }
                return true
            } isTargeted: { over in
                if over { dropTarget = tab.id } else if dropTarget == tab.id { dropTarget = nil }
            }
            .overlay(alignment: landsAfter ? .trailing : .leading) {
                // After this one when the dragged tab comes from the left, before it otherwise.
                if dropTarget == tab.id {
                    Capsule()
                        .fill(Color(model.color(of: tab), \.solid))
                        .frame(width: 3, height: 20)
                        .offset(x: landsAfter ? 5 : -5)
                }
            }
    }

    /// Whether the dragged tab lands after this one (it comes from its left), as
    /// `moveTab` puts it in this one's place.
    private var landsAfter: Bool {
        let tabs = model.patternTabs
        guard let dragged, let from = tabs.firstIndex(where: { $0.id == dragged }),
              let to = tabs.firstIndex(where: { $0.id == tab.id })
        else { return false }
        return from < to
    }
}

/// A tab: the Pattern's Glyph, name and Match count on a pill in its tint, or
/// filled solid when selected. The solid fill is one capsule shared by the tabs,
/// so it slides to the newly selected one, changing color on the way.
private struct TabPill: View {
    let tab: InspectorTab
    let color: PatternColor
    let isSelected: Bool
    let selection: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.glyph.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                Text("\(tab.entries.count)")
                    .monospacedDigit()
                    .opacity(0.7)
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(Color(color, isSelected ? \.onSolid : \.text))
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(Color(color, hovering ? \.strongTint : \.tint))
                if isSelected {
                    Capsule().fill(Color(color, \.solid))
                        .matchedGeometryEffect(id: "selectedTab", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(tab.title), \(tab.matchCountText)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A section header in the list layout: the disclosure, the Glyph, the name and a
/// count chip. A click anywhere on it collapses or expands the section.
private struct SectionHeader: View {
    static let height: CGFloat = 30

    let tab: InspectorTab
    let color: PatternColor
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
            Image(systemName: tab.glyph.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(color, \.text))
            Text(tab.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            Chip(text: "\(tab.entries.count)", color: color)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { isExpanded.toggle() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tab.title), \(tab.matchCountText)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isExpanded.toggle() }
    }
}

/// A row: a bar in the Pattern's color, the entry's index within its tab, then the
/// Summary over the faint raw preview (or the preview alone when there's no
/// Summary), and the parent chip of a nested Match.
private struct EntryRow: View {
    /// A row's height with its insets, for fitting the list to its rows.
    static let oneLineHeight: CGFloat = 28
    static let twoLineHeight: CGFloat = 46

    let entry: InspectorEntry
    let color: PatternColor
    let parentColor: PatternColor?
    let isSelected: Bool
    let readsAsUTC: Bool

    var body: some View {
        let summary = entry.summary?.text(readsAsUTC: readsAsUTC)
        HStack(alignment: summary == nil ? .center : .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(color, \.solid))
                .frame(width: 3, height: summary == nil ? 14 : 30)
                .padding(.top, summary == nil ? 0 : 2)
            Text("\(entry.index)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color.primary.opacity(0.4))
                .frame(minWidth: 18, alignment: .trailing)
                .padding(.top, summary == nil ? 0 : 2)
            if let summary {
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(isSelected ? Color(color, \.text) : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(entry.preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(isSelected ? 0.6 : 0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(entry.preview)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isSelected ? Color(color, \.text) : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let parent = entry.parent {
                Chip(text: parent.description, color: parentColor ?? Palette.plainText)
                    .padding(.top, summary == nil ? 0 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, summary == nil ? 4 : 5)
        .help(entry.tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel(summary: summary))
    }
}

/// The selected entry's Actions as pills: the first filled in the entry's solid
/// color with a "↩" hint (Return runs it), the others borderless with an icon.
struct ActionBar: View {
    let items: [ActionBarItem]
    let color: PatternColor
    let run: (ActionBarItem) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element) { position, item in
                if position == 0 {
                    PrimaryActionButton(item: item, color: color) { run(item) }
                } else {
                    ActionButton(item: item) { run(item) }
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }
}

private struct PrimaryActionButton: View {
    let item: ActionBarItem
    let color: PatternColor
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(item.title)
                Text("↩")
                    .font(.system(size: 11))
                    .opacity(0.75)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(color, \.onSolid))
            .padding(.leading, 13)
            .padding(.trailing, 9)
            .frame(height: 26)
            .background(Capsule().fill(Color(color, \.solid)).brightness(hovering ? 0.04 : 0))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(item.title) (Return)")
        .accessibilityLabel(item.title)
    }
}

private struct ActionButton: View {
    let item: ActionBarItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(item.title, systemImage: item.symbolName)
                .labelStyle(ActionLabelStyle())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(hovering ? Color.primary.opacity(0.07) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.8)
            configuration.title
        }
    }
}

/// A small capsule of text in a color's text role on its strong tint: a count, a
/// parent tag, a file's state.
struct Chip: View {
    let text: String
    let color: PatternColor

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color(color, \.text))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color(color, \.strongTint)))
    }
}

extension InspectorTab {
    /// "1 Match", "6 Matches".
    var matchCountText: String {
        counted(entries.count, "Match")
    }
}

extension InspectorEntry {
    /// What VoiceOver reads for a row: its index, then its Summary (or its text)
    /// and the Match it sits in.
    func accessibilityLabel(summary: String?) -> String {
        var label = "\(index): \(summary ?? preview)"
        if let parent { label += ", \(parent.description)" }
        return label
    }
}

/// Turns off the selection highlight of the table a row sits in, since rows draw
/// their own in their Pattern's color. Each row does it as it lands in the table,
/// which SwiftUI may build (or rebuild) at any point, such as when typing brings
/// the Inspector in.
private struct NoSystemHighlight: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var view = superview
            while let current = view, !(current is NSTableView) { view = current.superview }
            (view as? NSTableView)?.selectionHighlightStyle = .none
        }
    }
}
