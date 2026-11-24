import XCTest
@testable import PostManage

final class EditorUtilityTests: XCTestCase {
    func testJSONFormattingKeepsValuesAndRejectsInvalidInput() throws {
        let formatted = try JSONFormatting.pretty(#"{"b":true,"a":[1,"x"]}"#)
        XCTAssertTrue(formatted.contains("\n"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(formatted.utf8)) as? [String: Any])
        XCTAssertEqual(object["b"] as? Bool, true)
        XCTAssertEqual((object["a"] as? [Any])?.count, 2)
        XCTAssertThrowsError(try JSONFormatting.pretty("{bad json}"))
    }

    func testBulkEditRoundTripAndColonInValue() {
        let items = [KVItem(key: "Authorization", value: "Bearer a:b"),
                     KVItem(enabled: false, key: "Ignored", value: "no")]
        let text = KVBatchCodec.serialize(items)
        XCTAssertEqual(text, "Authorization: Bearer a:b\n// Ignored: no")
        let parsed = KVBatchCodec.parse(text, existing: items)
        XCTAssertEqual(parsed.map(\.id), items.map(\.id))
        XCTAssertEqual(parsed.map(\.value), items.map(\.value))
        XCTAssertEqual(parsed.map(\.enabled), [true, false])
    }
}
