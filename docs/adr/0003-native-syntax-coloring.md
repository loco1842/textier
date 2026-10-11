# Color JSON natively with VS Code themes instead of running Shiki

The Inspector shows parsed Matches syntax-colored, and the reference look was Shiki (VS Code-quality highlighting with VS Code themes). Only JSON has real structure to color among our Patterns (Shiki has no grammar for a standalone URL, file path or datetime), so we tokenize JSON with our own parser (ADR-0002) and color the tokens from bundled VS Code theme files (GitHub Light/Dark by default, user-supplied theme files allowed). That keeps zero dependencies and no JavaScript runtime, with output close to Shiki's.

## Considered Options

- **Shiki in a JavaScriptCore context** (measured 2026-10-09 on macOS 26): works without WebAssembly or a web view using `shiki/core` and the JavaScript regex engine. The bundle with JSON and log grammars plus two themes is about 192 KB minified, takes about 50 ms to load, and takes 100–125 ms to highlight 50 KB of JSON, so it has to run off the main thread. It needs Node at build time and a checked-in JS bundle. This is the path to take if we ever want many languages (whole log lines, HTTP dumps).
- **Shiki in a WKWebView**: rejected; it breaks the native text model that clickable URLs and file paths rely on.

**Update (2026-10-09, v5):** user-supplied theme files are no longer read. The JSON Viewer always colors with the bundled GitHub Light and Dark themes, and a new `appearance` setting (system, light or dark) picks which. A config's old `theme` key is ignored with a warning. The bundled themes are still VS Code theme files, so allowing user themes again later means reading the `theme` key again.
