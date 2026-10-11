# 05: URL and file path details

**What to build:** Selecting a URL or file path in the Inspector shows it parsed. A URL shows scheme, host, port, path, its query parameters in order with percent-decoded values (one row each), and fragment, each copyable. A file path shows the path, line and column (when present), and whether the file exists on this machine. These details come from the Inspection seam (the URL parts; the file location with `exists` from the `fileExists` lookup passed in, so tests never touch the disk).

Spec: `.scratch/textier-v2/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Panel and Inspector skeleton)

**Status:** done

- [x] The Monolog URL shows scheme `http`, host `app.bo.test`, path `/player/api/v1/signin`, no query
- [x] A URL like `https://a.test/x?q=a%20b&id=7#top` shows rows `q = a b`, `id = 7` in that order and fragment `top`; each value copies on click
- [x] A backtrace file path shows its path and line, and "exists" or "not found" correctly
- [x] Unit tests on the Inspection seam cover URL breakdown (ordered, decoded, repeated keys, no query) and file path detail with a stubbed `fileExists`

## Comments

**2026-10-09, implementation:** Built and committed; unit tests pass. URL breakdown and file path detail come from `inspect` (`InspectionDetail.swift`); `+` in a query is left as written.
- Automated: the matching suites in `Tests/TextierAppTests` cover the acceptance criteria in-process. Still to check by hand: steps 7 of `.scratch/textier-v2/manual-test.txt`.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
