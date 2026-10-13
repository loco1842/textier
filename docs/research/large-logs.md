# Large logs: where the time goes, and a path to 1 GB

Measured on 2026-10-11/12 on this Mac (Apple silicon, 8 cores), release build, with a synthetic log of about 100 bytes a line. One line in ten is an `ERROR` with a JSON payload, one a `WARNING` with a URL, one a `DEBUG` with a file path; the rest are `INFO` lines. The log level Preset is on, so each line has 3 Matches on average. The benchmark is `scripts/bench.sh` (tests that run only with `TEXTIER_BENCH` set).

## What it costs today

### Core (`inspect`, off the main thread)

| | 10k lines (1 MB) | 100k lines (9.8 MB) | 1M lines (99 MB) |
|---|---|---|---|
| `detect` (all Patterns, one thread) | 0.17 s | 1.8–2.1 s | ~20 s (extrapolated) |
| `inspect` (detect + an entry per Match, with details and summaries) | 0.9 s | 9.3–10.2 s | ~100 s (extrapolated) |
| Matches / Inspector entries | 31k / 50k | 310k / 500k (190k of them Plain Text pieces) | 3.1M / 5M |
| Each Pattern alone at 100k lines | | json 0.18 s, url 0.20 s, file path 0.28 s, log level 0.57 s, datetime 0.60 s | |

Building the entries (detail parsing, summaries, previews, Field links) costs four times the matching itself.

A risk at this scale: each Pattern has a fixed **2 s** budget per inspection (`Pattern.timeLimit`). From about 35 MB of logs, `datetime` and `log level` run out of it. They are then stopped and keep only the Matches found so far, with only a ⚠ badge saying so.

### App (the Panel)

| | 10k lines | 100k lines |
|---|---|---|
| Paste → pills and Inspector shown | 3.4 s | **38.7 s** |
| Selecting an entry in another tab (the JSON tab) | 2.2 s | **21.6 s** |
| Scroll to the end | 0.2 s | 2.1 s |
| One keystroke | 0.12 s, then a full re-inspection | 0.13 s, then **~39 s** of re-inspection |
| Memory added | ~125 MB | ~130 MB on top of the 10k run; ~30× the text |

### Where the main thread spends it (sampled at 100k lines)

1. **Recoloring pills: about 16 s of the 39 s.** `InputTextView.recolor` runs over the whole text whenever the selection changes. For each of 300k pills it builds `NSColor(patternColor:role:)`, which works out the Pattern color's roles for light and dark from hex: `String(format:)` and `pow` each time.
2. **The Inspector's SwiftUI `List`: about 8–12 s, and most of the 21 s tab switch.** `ForEach` diffs 100k rows (plus 190k Plain Text pieces) on every change (`ForEachState.applyNodes`, generic metadata lookups, copying `InspectorEntry`).
3. **Eager entries: about 8 s off the main thread.** Every Match gets its detail and summary up front, though only the rows on screen and the selected one ever show them.
4. **Detection on one core.** The Patterns run one after another, and each scans the whole text.

## What can't reach 1 GB, however fast

The text is one Swift `String`, copied into an `NSTextView`'s storage (UTF-16, 2 bytes a character). There is also an `InspectorEntry` (strings, preview, detail) per Match, and a pill and a color attribute per Match. That is about **30× the log in memory**: 30 GB for 1 GB. An editable `NSTextView` over hundreds of MB, with millions of temporary attributes, isn't workable either. Beyond about 100 MB, textier needs a different shape: a viewer that reads the file where it is, and an index instead of an entry per Match.

## Two building blocks, measured

**Parallel detection on chunks.** The text was split into ~1 MB chunks at line ends and every chunk detected on its own core (`DispatchQueue.concurrentPerform`):

| | one thread | 8 cores, 1 MB chunks |
|---|---|---|
| 100k lines (9.8 MB) | 1.82 s | **0.53 s** (3.4×), the same 310k Matches |
| 1M lines (99 MB) | ~20 s | **4.4 s**, 3.1M Matches (~22 MB/s) |

That puts a full index of **1 GB at about 45–50 s** in the background, before any prefiltering (skipping lines that can't hold a Pattern, e.g. no `http` → no URL).

**SQLite** (the system library, no dependency):

| | 310k Matches | 3.1M Matches |
|---|---|---|
| Insert (one transaction, a prepared statement) | 0.12 s | 0.96 s |
| Index on (Pattern, line) | 0.11 s | 0.95 s |
| `count(*)` of a Pattern | 1.8 ms | 19 ms |
| A page of 200 Matches from the middle | 0.1 ms | 0.1 ms |
| File size | 8 MB | 91 MB |

SQLite is fast enough, but a row per Match costs about **90 MB per 100 MB of log** (~900 MB at 1 GB). The index should keep less: per line, which Patterns matched. It can work out the Matches again for the lines on screen, which takes well under a millisecond for a screenful.

## Plan

### Phase 1: the current Panel, fast up to ~100 MB

Each of these stands on its own:

1. **Cache Pattern colors' roles and `NSColor`s**, keyed by `PatternColor`. This removes most of item 1 above, about 16 s at 100k lines.
2. **Recolor only what changed.** On a selection change, recolor the old and new selected ranges, not the whole text.
3. **Inspector list on `NSTableView`** (as the JSON Viewer already uses `NSOutlineView`): rows are made only for what's on screen and reused, and a tab switch doesn't diff 100k rows. Plain Text pieces are listed only when their tab is open.
4. **Lazy entries.** `InspectorEntry` keeps the Match and works out its detail, summary and Field links when first shown or selected, with a cache. That saves most of the 8 s.
5. **Parallel detection**: chunks at line ends on every core. JSON spanning lines needs care: run `json` over the whole text (it's quick, 0.18 s/10 MB), or overlap the chunks.
6. **Time limit by size**: scale `Pattern.timeLimit` with the input's size, or measure it per MB, so a big but healthy log isn't cut off.
7. **Incremental re-inspection on edit**: detect again only the lines an edit touched (plus a margin for JSON), not the whole text after every keystroke.

Expected: 100k lines from ~39 s to a few seconds to show, with instant tab switches and typing. This estimate is from the profile and isn't measured yet. Memory improves too, but stays several times the text.

### Phase 2: a Large Log view, 100 MB to 1 GB and beyond

For files (Open, drag and drop, or a paste over a threshold, saved to a temporary file), read-only:

- **The file stays on disk, memory-mapped.** It's never a whole `String`. A line index holds each line's offset: about 7M lines at 1 GB, so 56 MB as `UInt64` (less with block offsets).
- **A virtualized viewer.** An `NSTableView` (or a custom view) draws only the visible lines, with line numbers. Pills are detected per visible line as it scrolls, on the same Patterns, so they show at once on a 1 GB file before any indexing.
- **A background index**, built in parallel chunks with a progress bar (~45–50 s for 1 GB as measured, less with prefilters). Everything stays usable meanwhile. Per line it stores a bitmask of the Patterns that matched (2 bytes a line, 14 MB at 1 GB). Per Pattern it keeps aggregates: counts, top values (capped), and a datetime histogram (per minute, first and last time).
- **The Inspector redesigned for scale: facets, not rows.**
  - Each Pattern shows its count, top values (`ERROR` 12,031 · `WARNING` 3,442…, the top hosts or files) and, for `datetime`, a timeline.
  - A click on a Pattern, a value or a time range filters the viewer to those lines (a scan of 7M bitmasks takes milliseconds).
  - A Pattern's "list" is that filtered view, its Matches detected per visible row.
  - The selected Match opens in the card as today (JSON Viewer, details, Actions).
- **Search**: a literal or regex search over the mapped file in parallel chunks, its hits as one more filter, streaming in.
- **Storage**: SQLite keeps the index (line offsets and bitmasks as blobs, the aggregates), keyed by the file's path, size and modification date, so opening the same log again is instant. In memory at 1 GB: around 150–250 MB resident. The mapped file is paged by macOS, not held.
- **DuckDB isn't needed.** Our queries are bitmask filters and small aggregates, which SQLite or plain arrays answer in milliseconds. DuckDB would add a large C++ dependency (and an exception to ADR-0001's native stance) for columnar analytics textier doesn't do. Revisit if textier ever offers SQL-like queries over Field values ("group by `status` over 30M lines").

What stays as it is: the Panel for text you edit (small to medium, faster after Phase 1); the Selection Popover for selections (already capped at 1M characters, handing larger text to the Panel); Patterns, Grok and Color Rules, which the Large Log view uses unchanged.

Open questions:
- Multi-line records: pretty-printed JSON or stack traces in a log. The line index needs a "record" notion (a line starting with a timestamp starts a record), or JSON detection that reads past line ends from a `{`.
- Encodings other than UTF-8: convert them on open, or don't support them.
- Wrapped lines in a virtualized view: fixed-height rows without wrapping, with the full line in the card, is simplest.
- Whether a big paste in the Panel should become a Large Log view automatically, or offer it.

### Suggested order

1. Phase 1, items 1–4 (the profile's top three costs), measured again with the same benchmark: a few days.
2. Phase 1, items 5–7.
3. Phase 2 as its own feature: a spec and prototype of the facet Inspector first, then the mapped viewer, the background index and search.

## Phase 1 progress

`scripts/bench.sh 10000 100000` after each step (release build, this Mac). "shown" is paste to pills and Inspector; "select" is selecting the first entry of another tab; "reinspection" is a keystroke until the new inspection is shown.

| Step | lines | core inspect | shown | select | scroll to end | reinspection | memory |
|---|---|---|---|---|---|---|---|
| Baseline | 10k | 0.81 s | 4.04 s | 1.97 s | 0.22 s | 4.39 s | 123 MB |
| Baseline | 100k | 14.34 s (`url` stopped) | 40.29 s | 18.17 s | 2.31 s | 47.25 s | +112 MB |
| 1. Colors cached, selection recolors two ranges | 10k | 1.29 s | 1.75 s | 0.53 s | 0.26 s | 1.97 s | 116 MB |
| 1. Colors cached, selection recolors two ranges | 100k | 10.46 s | 15.20 s | 6.47 s | 2.46 s | 22.28 s | — |
