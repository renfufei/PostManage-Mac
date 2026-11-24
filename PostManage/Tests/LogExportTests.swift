import XCTest
@testable import PostManage

final class LogExportTests: XCTestCase {
    func testExportIncludesCompleteDisplayedMessagesAndRedaction() {
        let first = LogEntry(level: "SCRIPT", message: "AWSAccessKeyId=[REDACTED]")
        let second = LogEntry(level: "INFO", message: "Received 200")
        let output = LogExport.all([first, second])
        XCTAssertTrue(output.contains("[SCRIPT] AWSAccessKeyId=[REDACTED]"))
        XCTAssertTrue(output.contains("[INFO] Received 200"))
        XCTAssertEqual(output.components(separatedBy: "\n").count, 2)
    }
}
