# 04: Grok

**What to build:** A Pattern's regex can use grok. `%{NAME}` expands a Grok Definition; `%{NAME:field}` also makes a Field, and `%{NAME:field:int}`/`:float` is accepted with the type shown in the Field's label (`ms (int)`). Definitions can reference each other; `\%{` stays literal; an unknown name or a reference loop is an error naming it. textier bundles StreamSets' 69 definition names as one flat list, with bodies from Logstash's `logstash-patterns-core` `legacy` set (Apache-2.0, NOTICE shipped) and `HOST` as `%{HOSTNAME}`, each fixed where it relies on Oniguruma-only syntax (`\h` as a hex digit, Ruby's `(?m)`, a bare `{`). The config file gains a `grok` object for the user's own definitions, which replace bundled ones of the same name everywhere.

Spec: `.scratch/textier-v4/spec.md`. Vocabulary: `CONTEXT.md`. ADR-0004.

**Blocked by:** 03 (Fields)

**Status:** done

- [x] The nginx `access` Pattern `%{IPV4:client} - - \[%{HTTPDATE:time}\] "%{WORD:method} %{URIPATHPARAM:path}` written in the config file matches an nginx access line and shows four Fields in the Panel
- [x] All 69 StreamSets names are bundled and each compiles on its own
- [x] A `grok` entry `{"LOGLEVEL": "(?:WARN|ERR)"}` changes what `%{LOGLEVEL}` and the bundled definitions using it match
- [x] `%{NOPE}` and a loop `A → B → A` are warnings naming them; `\%{x}` matches the text `%{x}`
- [x] `%{NUMBER:ms:int}` compiles and its Field is labelled `ms (int)`
- [x] The `grok` key round-trips through the config file
- [x] Unit tests on the compile seam cover expansion, nesting, overrides, loops, `\%{`, types and the bundled library; `inspect` tests cover grok Fields on real log lines

## Comments

**2026-10-09, closed without the manual pass:** Implemented and committed on master (v4 commits 5e60b94..60ba734); the full suite passes and the acceptance criteria are covered by `Tests/TextierCoreTests` and `Tests/TextierAppTests`. The user closed it without running `.scratch/textier-v4/manual-test.txt`, which is kept for whenever the SwiftUI controls, menu bar and layout get a look by hand.
