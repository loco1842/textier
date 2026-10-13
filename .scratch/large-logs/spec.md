# Large logs, Phase 1: the Panel fast up to 100 MB

Status: ready-for-agent

Background and measurements: `docs/research/large-logs.md`. Phase 2 (a read-only Large Log view for 100 MB–1 GB) is out of scope here.

## Targets

Measured with the committed benchmark (`scripts/bench.sh`) on the development Mac, release build:

- 100k lines (~10 MB): paste → pills and Inspector shown in **≤ 2 s** (39 s before); a tab switch or entry selection **≤ 100 ms** (22 s); a keystroke never stalls and its re-inspection lands within **~2 s**; scrolling smooth.
- ~100 MB (1M lines): works, shown within ~15 s, with progress meanwhile.

## Decisions

1. **Colors**: a Pattern color's roles and `NSColor`s are cached. A selection change recolors only the old and the new selected range, never the whole Input.
2. **Inspector list on `NSTableView`** (both layouts: tabs, and one list with collapsible sections), looking and behaving as today: selection, arrows, Return, double-click, the row buttons, scrolling to the selection. Every entry is listed, no cap.
3. **Lazy entries**: a Match's detail, summary and Field links are worked out when its row first shows or it's selected, then kept. Plain Text pieces are worked out only when the Plain Text tab is open; its count shows at once.
   *Amended while building:* a row's height depends on whether its entry has a Summary, and the table needs every row's height up front, so Summaries stay eager. Profiling showed 60% of the entries' cost is datetimes (a `Calendar` and `String(format:)` per one), so entries are made fast instead: datetimes by arithmetic, entries built on every core. Plain Text pieces are built on every core too, rather than lazily, which keeps the Plain Text tab as it is.
4. **Parallel detection**: regex Patterns run over ~1 MB chunks split at line ends, on every core; `json` (and other Built-in Patterns) run over the whole text, so JSON spanning lines stays whole. Results are the same as detecting the whole text in one go.
5. **Time limit by size**: a Pattern's limit is 2 s plus 1 s per MB beyond 2 MB, counted across all its passes and chunks in one inspection. A stopped Pattern's warning: "‹name› was stopped after N s; some of its Matches may be missing".
6. **Progress**: while a large Input is inspected, the Panel shows "Inspecting… 40%", from chunks done.
7. **100 MB limit**: anything that would take the Panel's Input past 100 MB (a paste, typing, Open in Panel, the shortcut's fallback to the Panel) is refused; the Input stays as it was and the footer says "Too large for the Panel: 140 MB, the limit is 100 MB". Over 100 MB, the Selection Popover's "Too long to inspect here" doesn't offer Open in Panel.
8. **Edits** keep a full re-inspection (in the background, as today). Incremental re-inspection only if the keystroke target is missed.
9. **The Selection Popover** keeps its 1M-character cap.
10. **Benchmark**: committed as tests that run only with `TEXTIER_BENCH` set (core and app), and `scripts/bench.sh`. No timing assertions in CI; structural tests guard the fixes (e.g. a selection change recolors two ranges).

## Delivery

One commit per decision, each adding its before/after numbers to `docs/research/large-logs.md`; the full suite green at each; release v0.2.0 at the end.
