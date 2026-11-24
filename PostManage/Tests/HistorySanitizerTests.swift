import XCTest
@testable import PostManage

final class HistorySanitizerTests: XCTestCase {
    func testSensitiveQueryValuesAreHiddenWithoutChangingOtherParameters() {
        XCTAssertEqual(HistorySanitizer.url("https://example.test/path?user=alice&api_key=abc123&Signature=xyz#part"),
                       "https://example.test/path?user=alice&api_key=••••&Signature=••••#part")
    }
}
