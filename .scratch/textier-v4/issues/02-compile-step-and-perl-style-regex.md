# 02: Compile step and Perl-style regex

**What to build:** Patterns are written in Perl-style regex (ADR-0004), and one compile step decides what a regex means everywhere: config loading, detection and (later) Settings. It accepts the Python/PHP named-group spellings `(?P<n>…)`, `(?'n'…)` and `(?P=n)`, and gives every named group an internal name so any written name works (`client_ip`, `[client][ip]`), keeping a table back to the names as written. It rejects `\K`, recursion and subroutines (`(?R)`, `(?1)`, `(?&n)`), conditionals, branch reset, backtracking verbs and `(?^…)`, with an error naming the construct, and reports ICU's own errors with its reason. A config warning now says why a Pattern was skipped instead of "invalid regex". Regexes are compiled once per Config, not on every detection pass.

Spec: `.scratch/textier-v4/spec.md`. Vocabulary: `CONTEXT.md`. ADR-0004.

**Blocked by:** 01 (Shared Pattern names); both rework detection, so this follows it to avoid conflicts

**Status:** done

- [x] `(?P<id>\d+)`, `(?'id'\d+)` and `(?P<id>\d+)-(?P=id)` compile and match as Perl reads them
- [x] `a\Kb` is rejected with "\K isn't supported" (it no longer matches `aKb`); `(?R)`, `(?1)`, a conditional, `(?|…)`, `(*SKIP)` and `(?^…)` are each rejected by name
- [x] A named group called `client_ip` or `[client][ip]` compiles
- [x] A config with `a\Kb` loads with a warning naming `\K` and the Pattern, and the other Patterns still load
- [x] Detection results are unchanged for the shipped Patterns, and regexes aren't recompiled per pass
- [x] Unit tests on the compile seam cover each rewrite and each rejection; config tests cover the warnings

## Comments

**2026-10-09, closed without the manual pass:** Implemented and committed on master (v4 commits 5e60b94..60ba734); the full suite passes and the acceptance criteria are covered by `Tests/TextierCoreTests` and `Tests/TextierAppTests`. The user closed it without running `.scratch/textier-v4/manual-test.txt`, which is kept for whenever the SwiftUI controls, menu bar and layout get a look by hand.
