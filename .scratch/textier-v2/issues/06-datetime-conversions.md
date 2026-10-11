# 06: Datetime conversions

**What to build:** Selecting a datetime in the Inspector shows it converted: ISO 8601 UTC, local time with offset, epoch seconds, epoch milliseconds and relative time ("2 days ago"), each copyable. A datetime without an offset (Monolog's `2026-10-07 11:17:10`) is read as local time and labelled "assumed local", with a toggle to re-read it as UTC; `Z`/offset datetimes use their offset; 10/13-digit epochs are always UTC. The conversions come from the Inspection seam with `now` and the time zone passed in.

Spec: `.scratch/textier-v2/spec.md`. Vocabulary: `CONTEXT.md`.

**Blocked by:** 01 (Panel and Inspector skeleton)

**Status:** done

- [x] The Monolog datetime shows all five forms, labelled "assumed local"
- [x] The UTC toggle re-reads it as UTC and every form updates
- [x] `2026-10-07T11:17:10.123Z`, `1759835830` and `1759835830123` show the correct instant with no "assumed" label
- [x] Each form copies on click
- [x] Unit tests on the Inspection seam cover offset-less, `Z`, offset, fractional seconds, 10- and 13-digit epochs, the UTC re-read, and relative time with a fixed `now` and time zone

## Comments

**2026-10-09, implementation:** Built and committed; unit tests pass. Conversions in `InspectionDatetime.swift`; relative time is hand-rolled English so tests are locale-independent.
- Automated: the matching suites in `Tests/TextierAppTests` cover the acceptance criteria in-process. Still to check by hand: steps 7 of `.scratch/textier-v2/manual-test.txt`.

**2026-10-09, verified by hand:** The user ran the manual checks in `.scratch/textier-v2/manual-test.txt` against `build/Textier.app`; everything passed. Closed.
