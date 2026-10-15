// GitHub Light Default and GitHub Dark Default, from the GitHub VS Code theme
// (primer/github-vscode-theme) version 6.3.5, as published to Open VSX:
// https://open-vsx.org/api/GitHub/github-vscode-theme/6.3.5/file/GitHub.github-vscode-theme-6.3.5.vsix
// (`extension/themes/light-default.json` and `dark-default.json`), trimmed to the
// name, type, editor foreground/background and `tokenColors`.
//
// MIT License, Copyright (c) 2020 Primer; its notice is in textier's `NOTICE`.
//
// They're embedded as source rather than SwiftPM resources because the app bundle
// is assembled from the bare binary (`scripts/bundle.sh`).

/// The theme files `Theme.githubLight` and `Theme.githubDark` load.
enum BundledThemes {
    static let githubLight = #"""
    {
      "name": "GitHub Light Default",
      "type": null,
      "colors": {
        "editor.foreground": "#1f2328",
        "editor.background": "#ffffff"
      },
      "tokenColors": [
        {
          "scope": [
            "comment",
            "punctuation.definition.comment",
            "string.comment"
          ],
          "settings": {
            "foreground": "#6e7781"
          }
        },
        {
          "scope": [
            "constant.other.placeholder",
            "constant.character"
          ],
          "settings": {
            "foreground": "#cf222e"
          }
        },
        {
          "scope": [
            "constant",
            "entity.name.constant",
            "variable.other.constant",
            "variable.other.enummember",
            "variable.language",
            "entity"
          ],
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": [
            "entity.name",
            "meta.export.default",
            "meta.definition.variable"
          ],
          "settings": {
            "foreground": "#953800"
          }
        },
        {
          "scope": [
            "variable.parameter.function",
            "meta.jsx.children",
            "meta.block",
            "meta.tag.attributes",
            "entity.name.constant",
            "meta.object.member",
            "meta.embedded.expression"
          ],
          "settings": {
            "foreground": "#1f2328"
          }
        },
        {
          "scope": "entity.name.function",
          "settings": {
            "foreground": "#8250df"
          }
        },
        {
          "scope": [
            "entity.name.tag",
            "support.class.component"
          ],
          "settings": {
            "foreground": "#116329"
          }
        },
        {
          "scope": "keyword",
          "settings": {
            "foreground": "#cf222e"
          }
        },
        {
          "scope": [
            "storage",
            "storage.type"
          ],
          "settings": {
            "foreground": "#cf222e"
          }
        },
        {
          "scope": [
            "storage.modifier.package",
            "storage.modifier.import",
            "storage.type.java"
          ],
          "settings": {
            "foreground": "#1f2328"
          }
        },
        {
          "scope": [
            "string",
            "string punctuation.section.embedded source"
          ],
          "settings": {
            "foreground": "#0a3069"
          }
        },
        {
          "scope": "support",
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": "meta.property-name",
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": "variable",
          "settings": {
            "foreground": "#953800"
          }
        },
        {
          "scope": "variable.other",
          "settings": {
            "foreground": "#1f2328"
          }
        },
        {
          "scope": "invalid.broken",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#82071e"
          }
        },
        {
          "scope": "invalid.deprecated",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#82071e"
          }
        },
        {
          "scope": "invalid.illegal",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#82071e"
          }
        },
        {
          "scope": "invalid.unimplemented",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#82071e"
          }
        },
        {
          "scope": "carriage-return",
          "settings": {
            "fontStyle": "italic underline",
            "background": "#cf222e",
            "foreground": "#f6f8fa",
            "content": "^M"
          }
        },
        {
          "scope": "message.error",
          "settings": {
            "foreground": "#82071e"
          }
        },
        {
          "scope": "string variable",
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": [
            "source.regexp",
            "string.regexp"
          ],
          "settings": {
            "foreground": "#0a3069"
          }
        },
        {
          "scope": [
            "string.regexp.character-class",
            "string.regexp constant.character.escape",
            "string.regexp source.ruby.embedded",
            "string.regexp string.regexp.arbitrary-repitition"
          ],
          "settings": {
            "foreground": "#0a3069"
          }
        },
        {
          "scope": "string.regexp constant.character.escape",
          "settings": {
            "fontStyle": "bold",
            "foreground": "#116329"
          }
        },
        {
          "scope": "support.constant",
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": "support.variable",
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": "support.type.property-name.json",
          "settings": {
            "foreground": "#116329"
          }
        },
        {
          "scope": "meta.module-reference",
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": "punctuation.definition.list.begin.markdown",
          "settings": {
            "foreground": "#953800"
          }
        },
        {
          "scope": [
            "markup.heading",
            "markup.heading entity.name"
          ],
          "settings": {
            "fontStyle": "bold",
            "foreground": "#0550ae"
          }
        },
        {
          "scope": "markup.quote",
          "settings": {
            "foreground": "#116329"
          }
        },
        {
          "scope": "markup.italic",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#1f2328"
          }
        },
        {
          "scope": "markup.bold",
          "settings": {
            "fontStyle": "bold",
            "foreground": "#1f2328"
          }
        },
        {
          "scope": [
            "markup.underline"
          ],
          "settings": {
            "fontStyle": "underline"
          }
        },
        {
          "scope": [
            "markup.strikethrough"
          ],
          "settings": {
            "fontStyle": "strikethrough"
          }
        },
        {
          "scope": "markup.inline.raw",
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": [
            "markup.deleted",
            "meta.diff.header.from-file",
            "punctuation.definition.deleted"
          ],
          "settings": {
            "background": "#ffebe9",
            "foreground": "#82071e"
          }
        },
        {
          "scope": [
            "punctuation.section.embedded"
          ],
          "settings": {
            "foreground": "#cf222e"
          }
        },
        {
          "scope": [
            "markup.inserted",
            "meta.diff.header.to-file",
            "punctuation.definition.inserted"
          ],
          "settings": {
            "background": "#dafbe1",
            "foreground": "#116329"
          }
        },
        {
          "scope": [
            "markup.changed",
            "punctuation.definition.changed"
          ],
          "settings": {
            "background": "#ffd8b5",
            "foreground": "#953800"
          }
        },
        {
          "scope": [
            "markup.ignored",
            "markup.untracked"
          ],
          "settings": {
            "foreground": "#eaeef2",
            "background": "#0550ae"
          }
        },
        {
          "scope": "meta.diff.range",
          "settings": {
            "foreground": "#8250df",
            "fontStyle": "bold"
          }
        },
        {
          "scope": "meta.diff.header",
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": "meta.separator",
          "settings": {
            "fontStyle": "bold",
            "foreground": "#0550ae"
          }
        },
        {
          "scope": "meta.output",
          "settings": {
            "foreground": "#0550ae"
          }
        },
        {
          "scope": [
            "brackethighlighter.tag",
            "brackethighlighter.curly",
            "brackethighlighter.round",
            "brackethighlighter.square",
            "brackethighlighter.angle",
            "brackethighlighter.quote"
          ],
          "settings": {
            "foreground": "#57606a"
          }
        },
        {
          "scope": "brackethighlighter.unmatched",
          "settings": {
            "foreground": "#82071e"
          }
        },
        {
          "scope": [
            "constant.other.reference.link",
            "string.other.link"
          ],
          "settings": {
            "foreground": "#0a3069"
          }
        }
      ]
    }
    """#

    static let githubDark = #"""
    {
      "name": "GitHub Dark Default",
      "type": null,
      "colors": {
        "editor.foreground": "#e6edf3",
        "editor.background": "#0d1117"
      },
      "tokenColors": [
        {
          "scope": [
            "comment",
            "punctuation.definition.comment",
            "string.comment"
          ],
          "settings": {
            "foreground": "#8b949e"
          }
        },
        {
          "scope": [
            "constant.other.placeholder",
            "constant.character"
          ],
          "settings": {
            "foreground": "#ff7b72"
          }
        },
        {
          "scope": [
            "constant",
            "entity.name.constant",
            "variable.other.constant",
            "variable.other.enummember",
            "variable.language",
            "entity"
          ],
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": [
            "entity.name",
            "meta.export.default",
            "meta.definition.variable"
          ],
          "settings": {
            "foreground": "#ffa657"
          }
        },
        {
          "scope": [
            "variable.parameter.function",
            "meta.jsx.children",
            "meta.block",
            "meta.tag.attributes",
            "entity.name.constant",
            "meta.object.member",
            "meta.embedded.expression"
          ],
          "settings": {
            "foreground": "#e6edf3"
          }
        },
        {
          "scope": "entity.name.function",
          "settings": {
            "foreground": "#d2a8ff"
          }
        },
        {
          "scope": [
            "entity.name.tag",
            "support.class.component"
          ],
          "settings": {
            "foreground": "#7ee787"
          }
        },
        {
          "scope": "keyword",
          "settings": {
            "foreground": "#ff7b72"
          }
        },
        {
          "scope": [
            "storage",
            "storage.type"
          ],
          "settings": {
            "foreground": "#ff7b72"
          }
        },
        {
          "scope": [
            "storage.modifier.package",
            "storage.modifier.import",
            "storage.type.java"
          ],
          "settings": {
            "foreground": "#e6edf3"
          }
        },
        {
          "scope": [
            "string",
            "string punctuation.section.embedded source"
          ],
          "settings": {
            "foreground": "#a5d6ff"
          }
        },
        {
          "scope": "support",
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": "meta.property-name",
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": "variable",
          "settings": {
            "foreground": "#ffa657"
          }
        },
        {
          "scope": "variable.other",
          "settings": {
            "foreground": "#e6edf3"
          }
        },
        {
          "scope": "invalid.broken",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#ffa198"
          }
        },
        {
          "scope": "invalid.deprecated",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#ffa198"
          }
        },
        {
          "scope": "invalid.illegal",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#ffa198"
          }
        },
        {
          "scope": "invalid.unimplemented",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#ffa198"
          }
        },
        {
          "scope": "carriage-return",
          "settings": {
            "fontStyle": "italic underline",
            "background": "#ff7b72",
            "foreground": "#f0f6fc",
            "content": "^M"
          }
        },
        {
          "scope": "message.error",
          "settings": {
            "foreground": "#ffa198"
          }
        },
        {
          "scope": "string variable",
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": [
            "source.regexp",
            "string.regexp"
          ],
          "settings": {
            "foreground": "#a5d6ff"
          }
        },
        {
          "scope": [
            "string.regexp.character-class",
            "string.regexp constant.character.escape",
            "string.regexp source.ruby.embedded",
            "string.regexp string.regexp.arbitrary-repitition"
          ],
          "settings": {
            "foreground": "#a5d6ff"
          }
        },
        {
          "scope": "string.regexp constant.character.escape",
          "settings": {
            "fontStyle": "bold",
            "foreground": "#7ee787"
          }
        },
        {
          "scope": "support.constant",
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": "support.variable",
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": "support.type.property-name.json",
          "settings": {
            "foreground": "#7ee787"
          }
        },
        {
          "scope": "meta.module-reference",
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": "punctuation.definition.list.begin.markdown",
          "settings": {
            "foreground": "#ffa657"
          }
        },
        {
          "scope": [
            "markup.heading",
            "markup.heading entity.name"
          ],
          "settings": {
            "fontStyle": "bold",
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": "markup.quote",
          "settings": {
            "foreground": "#7ee787"
          }
        },
        {
          "scope": "markup.italic",
          "settings": {
            "fontStyle": "italic",
            "foreground": "#e6edf3"
          }
        },
        {
          "scope": "markup.bold",
          "settings": {
            "fontStyle": "bold",
            "foreground": "#e6edf3"
          }
        },
        {
          "scope": [
            "markup.underline"
          ],
          "settings": {
            "fontStyle": "underline"
          }
        },
        {
          "scope": [
            "markup.strikethrough"
          ],
          "settings": {
            "fontStyle": "strikethrough"
          }
        },
        {
          "scope": "markup.inline.raw",
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": [
            "markup.deleted",
            "meta.diff.header.from-file",
            "punctuation.definition.deleted"
          ],
          "settings": {
            "background": "#490202",
            "foreground": "#ffa198"
          }
        },
        {
          "scope": [
            "punctuation.section.embedded"
          ],
          "settings": {
            "foreground": "#ff7b72"
          }
        },
        {
          "scope": [
            "markup.inserted",
            "meta.diff.header.to-file",
            "punctuation.definition.inserted"
          ],
          "settings": {
            "background": "#04260f",
            "foreground": "#7ee787"
          }
        },
        {
          "scope": [
            "markup.changed",
            "punctuation.definition.changed"
          ],
          "settings": {
            "background": "#5a1e02",
            "foreground": "#ffa657"
          }
        },
        {
          "scope": [
            "markup.ignored",
            "markup.untracked"
          ],
          "settings": {
            "foreground": "#161b22",
            "background": "#79c0ff"
          }
        },
        {
          "scope": "meta.diff.range",
          "settings": {
            "foreground": "#d2a8ff",
            "fontStyle": "bold"
          }
        },
        {
          "scope": "meta.diff.header",
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": "meta.separator",
          "settings": {
            "fontStyle": "bold",
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": "meta.output",
          "settings": {
            "foreground": "#79c0ff"
          }
        },
        {
          "scope": [
            "brackethighlighter.tag",
            "brackethighlighter.curly",
            "brackethighlighter.round",
            "brackethighlighter.square",
            "brackethighlighter.angle",
            "brackethighlighter.quote"
          ],
          "settings": {
            "foreground": "#8b949e"
          }
        },
        {
          "scope": "brackethighlighter.unmatched",
          "settings": {
            "foreground": "#ffa198"
          }
        },
        {
          "scope": [
            "constant.other.reference.link",
            "string.other.link"
          ],
          "settings": {
            "foreground": "#a5d6ff"
          }
        }
      ]
    }
    """#
}
