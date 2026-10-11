# Motion: where textier animates, where it snaps, and what to add

Researched 2026-10-10 against the working tree (including commit c98aefa, which makes a click on a Match open it in the Inspector and a double-click copy it, `PanelController.swift:101-131`). API availability comes from Apple's SwiftUI docs via Context7. Anything marked **verify** was not checked on a running app.

## Bottom line

- Today only four things animate: the Inspector pane's fade and slide-in, the selected tab pill, row selection, and the List layout's section chevron. The Copied HUD also fades out. Everything else snaps, including the detail card, the header's count bar, the warnings badge, the Tabs/List switch, the Input's pills and the Panel itself.
- **Parsing is synchronous on the main thread.** For normal input the delay you notice is the 150 ms debounce, not parsing (about 7 ms for a 1 KB log line). Large input is another matter: 1.3 MB blocks the main thread for about 2 s, and 3.8 MB for about 13 s. A progress indicator can't draw while that happens, so a "working" state only makes sense after parsing moves off the main thread (L).
- **Rule for every new animation:** animate only alpha, offset, scale and color. Never delay `isHidden`, `isVisible`, frames, the split position or model state. The app tests read state 50 ms after an action (`Tests/TextierAppTests/Harness.swift:116`) and check `inspectorView.isHidden` and `frame.width` (`PanelTests.swift:27-28, 92-100`), `panel.isVisible` after Esc (`PanelTests.swift:112-116`), `CopiedHUD.panel?.isVisible` (`InputTests.swift:148`) and the text view's width (`InputTests.swift:348-358`). The existing pane fade passes these tests for exactly this reason: `isHidden` and the divider change synchronously (`PanelController.swift:193-205`), and only the SwiftUI opacity and offset animate.
- House style stays as it is: `.spring(duration: 0.25)` for selection, `.spring(duration: 0.3)` for tabs and `.easeOut(duration: 0.25)` for appearing. New work should use 150–250 ms.

## 1. Inventory

| Surface | Today | Where |
|---|---|---|
| Inspector pane first appears | **Animates**: opacity 0→1 and offset 14→0, easeOut 0.25, Reduce Motion gated | `InspectorView.swift:31-34` |
| Inspector pane hides (last Match deleted) | Snaps. `isHidden = true` runs before SwiftUI can fade, and the Input jumps wider | `PanelController.swift:193-205` |
| Input width when the pane comes or goes | Snaps (split `setPosition`). This is right: see "Avoid" | `PanelController.swift:203` |
| Tab switch | **Pill fill animates** (spring 0.3). The row list content and the list height (`fittedListHeight`) jump | `InspectorView.swift:239`, `:100-113` |
| Row selection | **Animates** (spring 0.25 on the rows' `ForEach`). The same `.animation(value: selection)` also animates any row insert or remove in the same transaction, such as an edit that moves the selection | `InspectorView.swift:95` |
| List-layout section collapse | **Animates** (`withAnimation` spring 0.25, chevron rotation and row insert/remove) | `InspectorView.swift:290-308` |
| Detail card swap on selection change | Snaps. The JSON Viewer is rebuilt by `.id(entry.text)`, and the Action bar items swap | `EntryDetailView.swift:13-18`, `InspectorView.swift:128-147` |
| Tree/Text mode switch | Snaps; NodeToolbar pops in and out | `EntryDetailView.swift:253-273` |
| JSON outline expand/collapse | AppKit default. Programmatic expand/collapse is unanimated (`expandItem` at `JSONViewer.swift:236, 486`, Expand/Collapse All at `EntryDetailView.swift:339-340`). `refreshValueCell` calls `noteHeightOfRows`, which AppKit animates for view-based tables, without the zero-duration group that `columnsDidResize` uses, so an escaped-JSON row's height change animates **regardless of Reduce Motion** | `JSONViewer.swift:268-274` vs `:348-351` |
| Layout Tabs ⇄ List (⌘L, header buttons) | Snaps: TabBar inserted or removed, list rebuilt | `InspectorView.swift:19-21`, `PanelView.swift:46-55`, `PanelController.swift:325-326` |
| Match pills in the Input | Snap in after the 150 ms debounce. Every change invalidates the **whole** document's display | `PanelController.swift:88-97`, `InputTextView.swift:159-185, 263` |
| Selected-Match ring in the Input | Snaps to the new range | `InputTextView.swift:174-180` |
| Match-count bar + "N Patterns · M Matches" | Snaps. `.transition(.opacity)` is **inert**: nothing gives it an animated transaction (no `withAnimation` around `inspect`, no `.animation` in this hosting view) | `PanelView.swift:61-64, 113-139` |
| Warnings badge | Snaps in and out, and its count snaps | `PanelView.swift:65-67, 142-175` |
| Panel show / hide | Snaps (`makeKeyAndOrderFront`, `orderOut`), borderless NSPanel | `PanelController.swift:33-40, 72, 313-315` |
| Match Window open | `makeKeyAndOrderFront` on a titled window with the default `animationBehavior`. It probably already gets AppKit's document-window animation (**verify**) | `MatchWindow.swift:67-72` |
| Copy feedback (now a double-click on a Match, or any CopyRow click) | HUD appears instantly and fades out after 900 ms (0.25 s, Reduce Motion gated). CopyRow's `doc.on.doc` icon gives no confirmation | `Actions.swift:154-173`, `EntryDetailView.swift:216-219` |
| Glass header buttons | System `.glassEffect(.regular.interactive())` press and hover motion | `PanelView.swift:82` |

**Reduce Motion consistency.** The SwiftUI sites read `@Environment(\.accessibilityReduceMotion)` (`InspectorView.swift:12, 223, 286`) and the HUD reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (`Actions.swift:166`). Two gaps: the outline's `noteHeightOfRows` animation (above) and AppKit's own outline animations, which never consult it. The v5 spec (story 69) says *no animation at all* under Reduce Motion. That is stricter than Apple's guidance, which allows short dissolves. This report keeps the stricter rule. Reduce Transparency (on for this user) doesn't change motion, but it flattens glass, so glass-morph effects would barely be visible to them.

## 2. The parsing process

**Where it runs.** `PanelModel.inspect` (`PanelModel.swift:56-70`) calls `TextierCore.inspect` synchronously on the main actor. It is called from:

- the 150 ms run-loop `Timer` after each edit (`PanelController.swift:90`);
- `show(input:)` before the Panel is shown (`PanelController.swift:52`, then `show()` at `:56`);
- `configDidChange` (`:62`).

After that, `onInspectionChange` sets `textView.matches`. `highlight()` strips and re-adds temporary attributes over the whole text and builds every pill (`InputTextView.swift:159-185`), and the pill `didSet` invalidates display for the full range (`:263`). SwiftUI then diffs the new `Inspection` and rebuilds the List.

**Measured** (standalone `swiftc -O` build of `Sources/TextierCore`, the Monolog fixture line from `Tests/TextierCoreTests/Fixtures.swift` repeated N times, default Config, Apple silicon, this Mac). The timings cover the core only, not SwiftUI or TextKit:

| Input | `inspect` total | of which `detect` | Matches / Inspector entries |
|---|---|---|---|
| 1 line, 1 KB | 7 ms | – | 2 / 10 |
| 10 lines, 12 KB | 9 ms | – | 20 / 100 |
| 100 lines, 127 KB | 104 ms | 26 ms (jsonRanges 10) | 200 / 1 000 |
| 300 lines, 383 KB | 407 ms | 159 ms | 600 / 3 000 |
| 1 000 lines, 1.3 MB | 2.1 s | 1.3 s (jsonRanges 111 ms) | 2 000 / 10 000 |
| 3 000 lines, 3.8 MB | 13.3 s | – | 6 000 / 30 000 |

Real disk `fileExists` checks barely change the totals (2 087 ms vs 2 113 ms stubbed at 1.3 MB). The fixture is match-dense, so plain logs will be faster.

**Superlinear.** Going from 127 KB to 1.3 MB is 10× the size but 20× the total time, and 51× for `detect`. Something in `resolveOverlaps`, `nest` or `plainTextEntries` grows worse than the regexes do. Filing that as a separate perf ticket is likely the cheapest large-input win. Moving work off the main thread hides the cost but doesn't remove it.

**What this means for motion:**

- **Typical input (< 50 KB):** no spinner or progress bar. They would flash for one frame. The useful motion is a short **fade-in of new pills** and of the count bar after the debounce, so a re-inspection reads as a settle rather than a flicker.
- **Large input:** a hotkey capture of MB-size text shows nothing for seconds, because parsing runs *before* `show()`. Even an indeterminate indicator can't draw while the main thread is blocked.
- **Off-main sketch (L).**
  1. Show the Panel with the raw text at once.
  2. Snapshot `AppConfig.current` on the main thread and run `inspect` in `Task.detached`. `Config`, `Inspection` and `Match` are `Sendable`; the regex cache is `Mutex`-guarded (`RegexCompile.swift:81`); `fileExists` must be a `@Sendable` closure.
  3. Tag each request with a generation counter and drop stale results, since `inspect` has no cancellation points.
  4. Deliver the result through `RunLoop.main.perform` or a `Timer`, not `Task { @MainActor }`. A main-queue hop doesn't run in the in-process app tests (`docs/agents/testing.md`); `JSONViewer.columnsDidResize` (`JSONViewer.swift:344`) already uses `RunLoop.main.perform` for this.
  5. While a pass is in flight and has run longer than about 200 ms, show a header shimmer or `ProgressView().controlSize(.small)` in place of `MatchCounts`, then fade the pills and the Inspector in when the result lands.
  6. Tests: `Harness.capture()` and `waitForInspection()` would need to wait for the generation to settle instead of a fixed `spin`.
  7. `highlight()` and the whole-range invalidation still cost main-thread time at MB sizes. Limit them to the visible glyph range as part of the same work.

## 3. Candidate animations

| # | Animation | Where | API | Effort | Risk | Reduce Motion |
|---|---|---|---|---|---|---|
| A | Count bar and match count: segments resize, number rolls, bar fades in and out (makes the dead `.transition` live) | `PanelView.swift:61-64, 113-139` | `.animation(.spring(duration: 0.25), value: model.patternTabs.map(\.entries.count))` on the header, `.contentTransition(.numericText(value: Double(matches)))` on `countLine` (macOS 14+) | S | Low: pure SwiftUI, no state deferred | env `reduceMotion ? nil : …` |
| B | Detail card crossfade when the selection changes; Action bar items too | `InspectorView.swift:128-147`, `EntryDetailView.swift:13-18` | `.id(selection)` + `.transition(.opacity)` with `.animation(.easeOut(duration: 0.15), value: selection)` scoped to `detail` | S | Low–Med: the old and new NSOutlineView coexist for 150 ms. Arrow-key scrubbing stays responsive because only opacity animates. Avoid `.blurReplace` on hosted AppKit views; it's unclear whether SwiftUI effects render on them. Now that a single click on a Match selects it, this fires often, which is good value | env |
| C | Warnings badge pops in, count rolls, triangle bounces on increase | `PanelView.swift:65-67, 142-155` | `.transition(.scale(0.8).combined(with: .opacity))`, `.contentTransition(.numericText(value:))`, `.symbolEffect(.bounce, value: warnings.count)` (macOS 14+), `.animation(value: model.warnings)` | S | Low | env. `symbolEffect` should be skipped explicitly under Reduce Motion |
| D | Copy confirmation: the HUD fades and scales in (it already fades out); CopyRow's icon swaps to a checkmark for about 1 s | `Actions.swift:154-160`, `EntryDetailView.swift:216-219` | HUD: `NSAnimationContext.runAnimationGroup` on `alphaValue` 0→1 (150 ms). Row: `Image(systemName: copied ? "checkmark" : "doc.on.doc").contentTransition(.symbolEffect(.replace))` | S | Low. `isVisible` must stay true at once (InputTests:148); only `alphaValue` animates | NSWorkspace flag / env |
| E | Inspector pane hide: fade out before `isHidden` | `PanelController.swift:193-205` | — | M | **Breaks** the synchronous `isHidden` checks (`PanelTests.swift:95`). Skip; the hide is rare (deleting the last Match) | — |
| F | Fade-in of new pills after re-inspection; ring crossfade on selection | `InputTextView.swift:159-185, 257-314` | Option 1: `CATransition(type: .fade, duration: 0.15)` added to the text view's layer (layer-backed through `FadingScrollView.wantsLayer`, `PanelController.swift:376`) just before `needsDisplay`. It crossfades the whole rendered tile, so text, selection and caret fade too (**verify** with NSTextView's tiled layers). Option 2: give each pill an alpha, diff new against previous pills by `(range, text)`, drive about 10 frames with `NSView.displayLink(target:selector:)` (macOS 14+), and invalidate only those pills' glyph ranges. Animate only for debounced and Highlighting (⌘E) changes, not `show(input:)`, where pills arrive with the window | M | **TextKit redraw cost.** `pills.didSet` invalidates the whole document (`InputTextView.swift:263`), so a frame-driven fade has to change that first or it redraws MB of text 10× per fade. Tests read `textView.pills` (model state), which stays synchronous | flag off → set at once |
| G | Tab switch: a sliding selection capsule that morphs color between pills; the list height eases | `InspectorView.swift:221-276, 22` | `matchedGeometryEffect(id: "selectedTab", in: ns)` on the solid capsule background, plus `.animation` on `fittedListHeight` | M | Med: the capsule and the color differ per tab. If the list-height animation runs inside `ResizableSplit`'s GeometryReader it can fight the drag gesture, so animate only when `topHeight == nil` | env |
| H | Tabs ⇄ List switch: TabBar slides up and away, list reflows | `InspectorView.swift:19-21`, `PanelView.swift:50, 54`, `PanelController.swift:326` | `withAnimation(.spring(duration: 0.25)) { model.layout = … }` + `.transition(.move(edge: .top).combined(with: .opacity))` on TabBar | S–M | Med: **SwiftUI List glitches.** Switching rebuilds every row of an NSTableView-backed List, and animated bulk inserts can stutter or misplace rows. ListLayoutTests is already flaky (`docs/agents/testing.md`); an animated transaction may worsen `listRowCount` timing. Animate TabBar only, and wrap only the layout change | env |
| I | Tree ⇄ Text crossfade; NodeToolbar fades | `EntryDetailView.swift:253-273` | `.animation(.easeOut(duration: 0.15), value: mode)` + `.transition(.opacity)` | S | Low, low value | env |
| J | JSON outline expand/collapse animated, gated | `JSONViewer.swift:236, 486`, `EntryDetailView.swift:339-340` | `outlineView.animator().expandItem(_:)` (**verify** AppKit animates through the proxy). Wrap `refreshValueCell`'s `noteHeightOfRows` in a group whose duration is 0 under Reduce Motion | S | Med: Expand All on a large subtree animated is slow; keep Expand/Collapse All unanimated | NSWorkspace flag; **fixes the existing gap** |
| K | Panel show/hide: quick fade and scale-in (0.15 s); fade on Esc | `PanelController.swift:33-40, 72, 313` | `panel.animationBehavior = .utilityWindow` (**verify** on a borderless NSPanel, and that `isVisible` still flips synchronously on `orderOut`), or manual: `alphaValue = 0` → `animator().alphaValue = 1`. For hide, fade then `orderOut` in the completion | M | Show: low. **Hide: breaks** `PanelTests.swift:112-116` unless `orderOut` runs first or the tests wait. A hotkey tool should open instantly, so keep it ≤ 150 ms | NSWorkspace flag |
| L | Header glass groups morph when buttons change | `PanelView.swift:34-58` | `glassEffectID(_:in:)` + `glassEffectTransition(.matchedGeometry)` in the existing `GlassEffectContainer` (macOS 26) | S | Nothing changes structure today, so there's nothing to morph; barely visible with Reduce Transparency | system |
| M | "Working" indicator for large input | header, in place of `MatchCounts` | `ProgressView().controlSize(.small)` or a `phaseAnimator` shimmer on the count bar | – | Needs §2's off-main work first; useless before it | static under Reduce Motion |

**One Reduce Motion helper.** The AppKit side reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` ad hoc today. Add a single `Motion` helper with `static var isReduced` and `static func animate(_ duration:, _ changes:)`, refreshed on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, and use it for D, F, J and K. On the SwiftUI side, keep the `reduceMotion ? nil : animation` pattern and pick durations from one shared place. Bridging is available: `NSAnimationContext.animate(_ animation: Animation, changes:completion:)` (macOS 15+) runs AppKit changes on a SwiftUI spring, and `NSViewRepresentableContext.animate(changes:completion:)` syncs a representable with the SwiftUI transaction. Either lets F and K reuse `.spring(duration: 0.25)` exactly.

## 4. Recommendation

**First batch** (all S, all SwiftUI or alpha-only, so no test behaviour changes; together about a day):

1. **A, the count bar and number roll.** It makes the inert `.transition(.opacity)` work, and it's the most visible "parsing finished" cue after each debounced pass.
2. **B, the detail card crossfade (150 ms).** Every click on a Match now changes the selection, so this is where the most frequent abrupt change sits.
3. **C, the warnings badge** (pop-in, numeric roll, bounce on increase).
4. **D, copy confirmation** (HUD fade-in plus a `.symbolEffect(.replace)` checkmark on CopyRow). This matters more now that copying is a double-click with no visible change in the Input.
5. **J's Reduce Motion fix only:** wrap `refreshValueCell`'s `noteHeightOfRows` (`JSONViewer.swift:272`) so it doesn't animate under Reduce Motion, and add the `Motion` helper for later AppKit work.

**Next:** F, the pill fade (prototype Option 1 first; adopt Option 2 only if the crossfade shows the caret or selection flickering), then G, the sliding tab capsule. Start the §2 perf ticket (the superlinear `detect`) before any progress UI.

**Avoid:**

- **Animating the NSSplitView divider or the Input's width.** Every frame rewraps and relays out the TextKit 1 text, and it breaks the synchronous width checks. The pane's offset and fade already mask the jump.
- **Delaying `isHidden`, `orderOut`, `isVisible` or model selection** for the sake of an exit animation (E, K-hide). The tests read them at once, and the user expects Esc to be instant.
- **Spinners or progress for normal-size input.** Parsing takes milliseconds, and a flash of a spinner reads as slowness.
- **Animating every keystroke-driven re-inspection inside the List** (row insert/remove springs), which leads to List glitches and jitter while typing. Consider narrowing `InspectorView.swift:95` so the spring applies to the selection background only, not to row diffs.
- **Animating Expand All or Collapse All** on large JSON.
- **`blurReplace` or other effect transitions over NSViewRepresentable content** (JSON Viewer, Text mode). Use opacity.
- **Glass morphing as a feature for this user.** Reduce Transparency flattens it.
- Anything that relies on `Task.sleep` or `Task { @MainActor }` timing in the app tests (`docs/agents/testing.md`). Use run-loop `Timer`s or `RunLoop.main.perform`.
