# Perl-style regex on ICU, not PCRE2

Patterns are written in Perl-style regex, but textier keeps compiling them with ICU (`NSRegularExpression`) instead of vendoring PCRE2. ICU already covers the syntax log-detection regexes use: named groups, `\k<n>`, possessive and atomic groups, lookaround, `\p{…}`, POSIX classes, `\Q…\E` and `(?x)`. Before compiling, textier rewrites the named-group spellings people paste from Python and PHP (`(?P<n>…)`, `(?'n'…)`, `(?P=n)`) and gives every named group an internal name, because ICU only accepts `[A-Za-z][A-Za-z0-9]*` and grok Field names like `client_ip` or `[client][ip]` don't fit. Everything ICU can't do (recursion, subroutines, conditionals, branch reset, backtracking verbs, unbounded lookbehind) is a compile error that names the construct. That includes `\K`, which ICU otherwise accepts silently as a literal `K`, so no regex quietly means something other than what was written.

## Considered Options

- **PCRE2** (vendored C library, 16-bit mode so ranges stay UTF-16): full Perl syntax. Rejected for now: a C dependency to build and update, for features almost no detection regex needs. If one is ever needed, PCRE2 can replace ICU inside the Pattern-compiling step without changing the config format.
- **Java (`java.util.regex`) compatibility, as StreamSets uses**: dropped. ICU and Java already share nearly all syntax; matching Java's ASCII-only `\w` and `\d` would have meant rewriting regexes in ways that surprise anyone writing ICU or Perl ones.

**Update (2026-10-11):** character classes keep ICU's reading, not Perl's. Perl reads an unescaped `[` inside a class as a literal; textier, like ICU and Oniguruma, reads it as a nested class, and `&&` and `--` inside a class are set operators. Write `\[` for a literal `[`. Grok input relies on this: Logstash definitions people paste, such as `UNIXPATH`'s `[[[:alnum:]]_…]`, nest classes. A class left open by a `[` meant as a literal is an error saying to write `\[`.
