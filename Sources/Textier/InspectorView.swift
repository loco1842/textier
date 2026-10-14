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
        // The values the list shows are read here, so SwiftUI updates it when they change.
        EntryList(
            model: model, tabsRevision: model.tabsRevision, layout: model.layout, collapsed: model.collapsed,
            selection: model.inspection.selection, readsAsUTC: model.readsDatetimeAsUTC,
            listHasFocus: model.listHasFocus
        )
        .mask(EdgeFade(bottom: 12))
    }

    /// The row list's height before the divider is dragged: its rows', up to a cap,
    /// so the Action bar and card follow right under them.
    private var fittedListHeight: CGFloat {
        let cap: CGFloat = model.layout == .tabs ? 206 : 290
        // Rows are added up only until they pass the cap: a large Input has many.
        var rows: CGFloat = 0
        func add(_ tab: InspectorTab) {
            for entry in tab.entries {
                guard rows <= cap else { return }
                rows += EntryRow.height(of: entry)
            }
        }
        switch model.layout {
        case .tabs:
            model.selectedTab.map(add)
        case .list:
            for tab in model.inspection.tabs where rows <= cap {
                rows += SectionHeader.height
                if !model.isCollapsed(tab.id) { add(tab) }
            }
        }
        return min(cap, rows + 4)
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
        HStack(spacing: 4) {
            tabs
            // The selected tab's order; Plain Text keeps its own.
            if let tab = model.selectedTab, let kind = tab.sortKind {
                SortMenu(kind: kind, order: model.order(of: tab.id)) { model.setOrder($0, of: tab.id) }
                    .padding(.trailing, 10)
                    .padding(.top, 4)
            }
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(model.inspection.tabs.enumerated()), id: \.element.id) { number, tab in
                    let pill = TabPill(
                        tab: tab, color: model.color(of: tab), isSelected: model.selectedTab?.id == tab.id,
                        selection: selection
                    ) {
                        model.selectTab(tab.id)
                    }
                    .help(
                        (number < 9 ? "\(tab.title) (\(Shortcut.symbols(of: AppConfig.store.config.shortcuts.selectTab))\(number + 1))" : tab.title)
                            + (tab.id == .plainText ? "" : " — drag to move")
                    )
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
/// count chip. A click anywhere on it collapses or expands the section (the list
/// handles the click; VoiceOver's action toggles it here).
struct SectionHeader: View {
    static let height: CGFloat = 30

    let tab: InspectorTab
    let color: PatternColor
    @Binding var isExpanded: Bool
    /// The section's order, and how to change it; nil for Plain Text.
    var sorting: (order: EntryOrder, choose: (EntryOrder) -> Void)?
    /// The sort menu shows while the pointer is over the header, or once sorted.
    @State private var hovering = false

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
            if let sorting, let kind = tab.sortKind, hovering || sorting.order != .position {
                SortMenu(kind: kind, order: sorting.order, choose: sorting.choose)
            }
            Chip(text: "\(tab.entries.count)", color: color)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .onHover { hovering = $0 }
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
struct EntryRow: View {
    /// A row's height with its insets, for fitting the list to its rows.
    static let oneLineHeight: CGFloat = 28
    static let twoLineHeight: CGFloat = 46

    /// Two lines with a Summary, one without.
    static func height(of entry: InspectorEntry) -> CGFloat {
        entry.summary == nil ? oneLineHeight : twoLineHeight
    }

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
        .help(help)
    }

    /// Pop Out's tooltip has its shortcut, as the Config sets it.
    private var help: String {
        guard item == .popOut, let shortcut = AppConfig.store.config.shortcuts[.popOut] else { return item.title }
        return "\(item.title) (\(shortcut.symbolText))"
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

/// A tab's sort menu: Position, then its two value orders (Earliest or Latest
/// first, A → Z or Z → A). It shows the order when the tab is sorted, and just
/// its icon at Position.
struct SortMenu: View {
    let kind: SortKind
    let order: EntryOrder
    let choose: (EntryOrder) -> Void

    var body: some View {
        Menu {
            ForEach(EntryOrder.allCases, id: \.self) { option in
                Button {
                    choose(option)
                } label: {
                    if option == order {
                        Label(kind.title(of: option), systemImage: "checkmark")
                    } else {
                        Text(kind.title(of: option))
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                if order != .position {
                    Text(kind.title(of: order))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(order == .position ? .secondary : .primary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(Color.primary.opacity(order == .position ? 0 : 0.08)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort: \(kind.title(of: order))")
        .accessibilityLabel("Sort, \(kind.title(of: order))")
    }
}
