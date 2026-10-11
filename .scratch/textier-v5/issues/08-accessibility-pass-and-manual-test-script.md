# 08: Accessibility pass and manual test script

**What to build:** VoiceOver reads every new control. The header's glass buttons read with their names and states, the warnings badge with its count, tabs with their Pattern name and Match count, and rows with their Summary (or text) and index. Contrast holds in both appearances. Reduce Motion stops all animation, and Reduce Transparency makes the window, the pane and the Match Window opaque.

`.scratch/textier-v5/manual-test.txt` is written in the style of v1–v4's. Its steps walk through:
- light and dark, Reduce Transparency and Reduce Motion;
- each Pattern's pill, tab and row, and a nested selection;
- the warnings badge, the empty placeholder, the List layout and a Match Window;
- comparing each against mockup variant E.

Spec: `.scratch/textier-v5/spec.md` (stories 4, 69–71; Testing Decisions: the look is checked by hand). Vocabulary: `CONTEXT.md`.

**Blocked by:** 02 (Borderless frosted Panel and header), 03 (Pills in the Input), 05 (Summaries and two-line rows), 06 (Action bar and cards), 07 (Match Window in the new style)

**Status:** ready-for-agent

- [ ] VoiceOver names the header buttons and their states, the badge count, each tab with its count, and each row with its Summary
- [ ] Reduce Motion: no animations anywhere; Reduce Transparency: no blur in the Panel, pane or Match Window
- [ ] `manual-test.txt` exists, numbered, covering every state above, with "step N: what you saw" reporting as in earlier versions
- [ ] The full suite passes (`scripts/test.sh`), allowing the known flaky list-layout test after a rerun
