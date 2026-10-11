# 03: Fields

**What to build:** Named captures become Fields. A Match of a regex Pattern with named groups shows a Fields block in its parsed view, in the Inspector and in Match Windows: one row per capture that took part in the Match, labelled with the name as written, in regex order, a repeated name giving a row each. The rows sit above the Match's own parsed view (URL parts, datetime conversions, file path, or its text). A row copies its value on click, and a value that's a URL or file path Match in its entirety offers that Match's Actions. Unnamed groups give no Field.

Spec: `.scratch/textier-v4/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 02 (Compile step and Perl-style regex)

**Status:** done

- [x] A User Pattern `(?<client>\d+\.\d+\.\d+\.\d+) (?<path>/\S+)` on an access-log line shows `client` and `path` rows in that order
- [x] An optional named group that didn't take part gives no row
- [x] `(?<tag>\w+) (?<tag>\w+)` (one name written twice, allowed because groups get internal names) gives two `tag` rows, in order
- [x] A group named `[client][ip]` shows under that name as written
- [x] A `path` Field that is a file path offers Open in Editor; a URL Field offers Open in Browser
- [x] A Pattern that offers `open-url` and has Fields shows the Fields rows, then the URL's parts
- [x] Unit tests on `inspect` cover order, repeats, skipped groups, link values and the combined detail
- [x] App tests cover the Field rows in the Inspector and a Match Window, and copying a row

## Comments

**2026-10-09, closed without the manual pass:** Implemented and committed on master (v4 commits 5e60b94..60ba734); the full suite passes and the acceptance criteria are covered by `Tests/TextierCoreTests` and `Tests/TextierAppTests`. The user closed it without running `.scratch/textier-v4/manual-test.txt`, which is kept for whenever the SwiftUI controls, menu bar and layout get a look by hand.
