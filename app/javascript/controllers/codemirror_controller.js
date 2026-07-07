import { Controller } from "@hotwired/stimulus"
import { EditorState } from "@codemirror/state"
import { EditorView, lineNumbers, highlightActiveLine, drawSelection } from "@codemirror/view"
import { defaultHighlightStyle, syntaxHighlighting } from "@codemirror/language"
import { yaml } from "@codemirror/lang-yaml"
import { linter } from "@codemirror/lint"
import { indentUnit } from "@codemirror/language"
import { indentationMarkers } from "@replit/codemirror-indentation-markers"
import * as yamlLib from "js-yaml"

// Wraps a <textarea> with a CodeMirror 6 YAML editor. The textarea stays
// in sync via the editor's updateListener — when the form submits, the
// textarea holds the latest content. Replaces the textarea in place.
//
// Usage:
//   <%= f.text_area :content, data: { controller: "codemirror" } %>
export default class extends Controller {
  connect() {
    const textarea = this.element
    this.editor = new EditorView({
      state: EditorState.create({
        doc: textarea.value,
        extensions: [
          lineNumbers(),
          highlightActiveLine(),
          drawSelection(),
          indentUnit.of("  "),
          indentationMarkers(),
          yaml(),
          syntaxHighlighting(defaultHighlightStyle),
          linter(this.validateYaml.bind(this)),
          EditorView.lineWrapping,
          EditorView.theme({
            "&": {
              backgroundColor: "#1a1a2e",
              color: "#e2e8f0",
              fontSize: "13px",
              fontFamily: "'JetBrains Mono', 'Fira Code', monospace"
            },
            ".cm-content": { caretColor: "#3b82f6" },
            ".cm-gutters": {
              backgroundColor: "#16213e",
              color: "#94a3b8",
              border: "none"
            },
            ".cm-activeLine": { backgroundColor: "#1e293b" },
            ".cm-activeLineGutter": { backgroundColor: "#1e293b" },
            "&.cm-focused": { outline: "none" },
            ".cm-lintRange-error": { textDecoration: "underline wavy #ef4444" }
          }),
          EditorView.updateListener.of((update) => {
            if (update.docChanged) textarea.value = update.state.doc.toString()
          })
        ]
      }),
      parent: textarea.parentNode
    })
    // Hide the textarea but keep it in the DOM for form submission.
    textarea.style.display = "none"
    // Place the editor right after the textarea.
    textarea.parentNode.insertBefore(this.editor.dom, textarea.nextSibling)
  }

  disconnect() {
    this.editor?.destroy()
  }

  // Simple YAML linter — parse the doc on each change, flag parse errors.
  validateYaml(view) {
    const text = view.state.doc.toString()
    try {
      yamlLib.default.load(text)
      return []
    } catch (err) {
      // Best-effort line extraction from js-yaml's error message.
      const lineMatch = err.mark?.line ? { line: err.mark.line, col: err.mark.column || 0 } : null
      if (!lineMatch) return []
      return [{
        from: view.state.doc.line(lineMatch.line + 1).from + lineMatch.col,
        to: view.state.doc.line(lineMatch.line + 1).from + lineMatch.col + 1,
        severity: "error",
        message: err.message
      }]
    }
  }
}
