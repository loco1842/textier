# 05: Summaries and two-line rows

**What to build:** Each Inspector entry gets a **Summary** from `inspect`, computed with the same `now` and time zone as its detail:
- **datetime:** the local `HH:mm:ss` (with the date when it isn't today), then the relative time. An offset-less datetime has both readings, assumed local and read as UTC, and the row follows the Panel's "read as UTC" choice;
- **file path:** the file name with "line L, col C" (or just the line, or nothing more);
- **URL:** the host;
- **JSON:** "N keys · k1, k2, k3…" for an object, "N items" for an array;
- **otherwise, with Fields:** up to three "label value" pairs;
- **otherwise:** none. Log level, a User Pattern without Fields, and every Plain Text entry have no Summary, and neither does a Summary equal to the entry's text.

Rows show a 3 pt leading bar in the Pattern's solid color, the index (numbered as today), and either the Summary over the faint, monospaced raw preview, or just the preview when there's no Summary. A nested Match's parent chip is tinted in the parent's Pattern color. The selected row takes its own strong tint in place of the system accent. A selection change animates with a short spring, except under Reduce Motion. Tab, Shift-Tab, the arrow keys, Return and double-click are unchanged.

Spec: `.scratch/textier-v5/spec.md` (stories 33–37, 40–47; Implementation Decisions: Summary, Rows). Visual reference: mockup variant E. Vocabulary: `CONTEXT.md` (Summary, not "preview").

**Blocked by:** 01 (Saturated palette and color roles), 04 (Inset Inspector pane, pill tabs and Glyphs)

**Status:** ready-for-agent

- [ ] Datetime Summaries cover today, another day, and an offset-less value under both readings, matching the parsed view's choice
- [ ] File path, URL, JSON object (more and fewer than three keys) and JSON array Summaries follow the spec
- [ ] A regex Pattern with Fields summarises its first three Fields; one without has no Summary
- [ ] Log level and Plain Text entries have no Summary and show one-line rows
- [ ] Rows show the color bar, the Summary over the raw text, and a parent chip in the parent's color
- [ ] The selected row is tinted in its own color, with no system accent
- [ ] Keyboard and double-click behaviour in the rows is unchanged
- [ ] Core tests in the style of `InspectionTests`/`FieldTests` cover every Summary rule with a fixed `now` and time zone; `InspectorTests` and `ListLayoutTests` pass unchanged

## Comments

If this runs in the same wave as 06, this ticket owns the rows and section list of the Inspector view; 06 owns the Action bar and the detail card.
