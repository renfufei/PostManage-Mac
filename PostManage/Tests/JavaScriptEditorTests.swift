import AppKit
import SwiftUI
import XCTest
@testable import PostManage

final class JavaScriptEditorTests: XCTestCase {
    func testHighlightsKeywordsStringsAndComments() {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        editor.string = "var token = 'abc'; // comment"
        JavaScriptEditor(text: .constant(editor.string)).makeCoordinator().highlight(editor)
        let storage = editor.textStorage!
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemPurple)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 12, effectiveRange: nil) as? NSColor, .systemRed)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 20, effectiveRange: nil) as? NSColor, .systemGreen)
    }
}
