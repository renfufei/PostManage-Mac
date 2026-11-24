import AppKit
import SwiftUI

struct JavaScriptEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let editor = NSTextView(frame: .zero)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textColor = .labelColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.string = text
        context.coordinator.highlight(editor)
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            let oldSelection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(oldSelection.location, (text as NSString).length), length: 0))
            context.coordinator.highlight(editor)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JavaScriptEditor
        init(_ parent: JavaScriptEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            highlight(editor)
        }

        func highlight(_ editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            let text = editor.string
            let range = NSRange(location: 0, length: (text as NSString).length)
            guard range.length > 0 else { return }
            storage.beginEditing()
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ], range: range)
            apply(#"\b(?:var|let|const|if|else|for|while|return|function|new|try|catch|throw|true|false|null|undefined)\b"#,
                  color: .systemPurple, in: text, storage: storage, range: range)
            apply(#"\b(?:pm|CryptoJS|console|Date)\b"#,
                  color: .systemBlue, in: text, storage: storage, range: range)
            apply(#"\b\d+(?:\.\d+)?\b"#,
                  color: .systemOrange, in: text, storage: storage, range: range)
            apply(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#,
                  color: .systemRed, in: text, storage: storage, range: range)
            apply(#"//[^\n]*|/\*[\s\S]*?\*/"#,
                  color: .systemGreen, in: text, storage: storage, range: range)
            storage.endEditing()
        }

        private func apply(_ pattern: String, color: NSColor, in text: String,
                           storage: NSTextStorage, range: NSRange) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: text, range: range) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
    }
}
