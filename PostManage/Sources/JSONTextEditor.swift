import AppKit
import SwiftUI

enum JSONFormatting {
    static func pretty(_ text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }
}

struct JSONTextEditor: NSViewRepresentable {
    @Binding var text: String
    var editable = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let editor = NSTextView(frame: .zero)
        editor.isRichText = false
        editor.isEditable = editable
        editor.isSelectable = true
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
        editor.isEditable = editable
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            context.coordinator.highlight(editor)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONTextEditor
        init(_ parent: JSONTextEditor) { self.parent = parent }

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
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                                   .foregroundColor: NSColor.labelColor], range: range)
            color(#"\b(?:true|false|null)\b"#, .systemPurple, text, storage, range)
            color(#"(?<![\w])[-]?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#, .systemOrange, text, storage, range)
            color(#""(?:\\.|[^"\\])*""#, .systemGreen, text, storage, range)
            color(#""(?:\\.|[^"\\])*"(?=\s*:)"#, .systemBlue, text, storage, range)
            storage.endEditing()
        }

        private func color(_ pattern: String, _ value: NSColor, _ text: String,
                           _ storage: NSTextStorage, _ range: NSRange) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: text, range: range) {
                storage.addAttribute(.foregroundColor, value: value, range: match.range)
            }
        }
    }
}
