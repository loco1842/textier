# 08: Settings: Grok Definitions

**What to build:** The Grok Definitions section lists the bundled definitions as one list, each with its regex, and the user's own definitions, each editable, with errors from the compile step shown inline; a user definition with a bundled name is marked "overrides bundled". Pasting `NAME regex` lines (from Logstash or StreamSets) adds them as the user's own. "New Pattern from this" on any definition adds a User Pattern named after it (lowercased, `_` as spaces) with the regex `%{NAME}` and Action `copy`, and opens it in the Pattern editor.

Spec: `.scratch/textier-v4/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 04 (Grok), 06 (Settings: Patterns list and editor)

**Status:** done

- [x] The bundled list shows all 69 definitions with their regex
- [x] Adding `MYTICKET [A-Z]+-\d+` writes it to the `grok` object; a Pattern `%{MYTICKET}` then matches `ABC-12`
- [x] Pasting three `NAME regex` lines adds three definitions; a line that isn't `NAME regex` is reported, not added
- [x] A user `LOGLEVEL` is marked "overrides bundled"; a loop shows its error and isn't written
- [x] "New Pattern from this" on `TIMESTAMP_ISO8601` adds the Pattern `timestamp iso8601` with `%{TIMESTAMP_ISO8601}` and opens it
- [x] The done scenario: building the nginx `access` Pattern in Settings shows its four Fields in the test box, then in the Panel
- [x] App tests cover adding, pasting, overriding and New Pattern from this through `SettingsModel`

## Comments

**2026-10-09, closed without the manual pass:** Implemented and committed on master (v4 commits 5e60b94..60ba734); the full suite passes and the acceptance criteria are covered by `Tests/TextierCoreTests` and `Tests/TextierAppTests`. The user closed it without running `.scratch/textier-v4/manual-test.txt`, which is kept for whenever the SwiftUI controls, menu bar and layout get a look by hand.
