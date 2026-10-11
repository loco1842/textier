# 03: Presets and the overlap/nesting rules

**What to build:** The Panel highlights every default Preset, not just URLs, and detection follows the spec's two rules. Presets added: datetime (`YYYY-MM-DD` with optional `T`/space time, fractional seconds, `Z`/offset; and 10- or 13-digit Unix epoch as a whole word), file path (absolute `/…` or `~/…`, optional `:line[:col]`), and log level (PSR-3 set as a whole word), shipped disabled. Each Preset carries its default Action list in first-Action order: URL → `open-url`, `copy`; file path → `open-file`, `copy` (the `open-file` Action is declared now and implemented in ticket 06, so until then it is listed but inert); datetime → `copy`; log level → `copy`. Overlap rule: when two candidate Matches overlap without containment, the longer wins, tie broken by Pattern order in Config. Containment: the inner Match becomes a child of the outer; the Panel highlights only top-level Matches. `open-url` opens the Match in the default browser. Disabled Patterns produce no Matches.

Spec: `.scratch/textier-v1/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Walking skeleton)

**Status:** done

- [x] The Monolog fixture line shows datetime, URL and file path Matches; log level is not highlighted (disabled)
- [x] Enabling the log level Preset in the in-code Config highlights `WARNING`
- [x] Double-clicking a URL opens it in the default browser; `copy` remains in its menu
- [x] A URL that also matches a file path regex yields one Match, the longer one; a tie goes to the Pattern earlier in Config
- [x] A Match fully inside another becomes its child and is not highlighted in the Panel
- [x] Unit tests cover each Preset's positives and near-miss negatives, longest-wins, config-order tie-break, containment-to-child, and disabled Patterns

## Comments

**2026-10-08, implementation:** Built and committed. 30 tests pass under `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`; `swift build` is clean.
- The first two items are covered at the detection seam (`DefaultConfigTests`, `LogLevelDetectionTests`), but the Panel itself still needs a look by hand.
- The file path Preset can't start mid-word or right after `:` or `/`, so the path part of a URL never matches it. With the shipped Presets a URL produces no file path candidate at all. The "longer wins" item is tested with a looser User-style Pattern that partially overlaps the Monolog URL, and with minimal strings for the tie-break. Paths end at whitespace, quotes, brackets, `,` `;` `:` `\`, and never on a trailing `.`. `:line[:col]` is part of the Match text, for ticket 06 to parse.
- Log level matches the uppercase PSR-3 words only (as Monolog writes them), so `error` in prose isn't highlighted.
- Identical ranges from two Patterns keep only the earlier Pattern's Match; it is not made a child of itself. Zero-length regex matches are ignored.
- Shared contract for the next tickets: `Pattern` is now `name`, `kind` (`.regex(String)` or `.builtin(BuiltinPattern)`, where `BuiltinPattern` is `json` / `escaped-json`), `enabled`, `actions`, `color: String?`, with a `Pattern(name:regex:…)` convenience init. Detection skips `.builtin` kinds for now; the hook is the `.builtin` case of `ranges(of:in:)` in `Detection.swift`. `Action` has the full vocabulary (`copy`, `open`, `copy-pretty`, `open-url`, `open-file`). `open`, `copy-pretty` and `open-file` have menu titles but do nothing until tickets 04 and 06. `Match` has `children` (ranges in Input coordinates) and a public init. `Config.default` is URL, datetime, file path, then log level (disabled).
- Still to check by hand: the Monolog line in the Panel shows the datetime, URL and six file paths highlighted, and no `WARNING`. Setting `Preset.logLevel` to enabled in `Config.default` highlights `WARNING`. Double-clicking the URL opens the browser, and its menu lists Open in Browser and Copy.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v1/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
