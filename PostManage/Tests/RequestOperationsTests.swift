import XCTest
@testable import PostManage

final class RequestOperationsTests: XCTestCase {
    func testDuplicateInsertsAfterSourceAndDetachesPostmanIdentity() throws {
        var first = RequestItem()
        first.name = "First"
        first.importKey = "postman-id"
        first.sortOrder = 0
        first.params = [KVItem(key: "id", value: "{{id}}")]
        var second = RequestItem()
        second.name = "Second"
        second.sortOrder = 1
        var collection = RequestCollection(name: "API", requests: [first, second])
        let id = try XCTUnwrap(RequestOperations.duplicate(first.id, in: &collection))
        let copy = try XCTUnwrap(collection.requests.first(where: { $0.id == id }))
        XCTAssertEqual(copy.name, "First Copy")
        XCTAssertNil(copy.importKey)
        XCTAssertNotEqual(copy.params.first?.id, first.params.first?.id)
        XCTAssertEqual(copy.params.first?.value, "{{id}}")
        XCTAssertEqual(collection.requests.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }.map(\.id), [first.id, id, second.id])
    }

    func testCopyCanPasteRepeatedlyAndCutMovesOriginal() throws {
        var request = RequestItem()
        request.name = "Lookup"
        let source = RequestCollection(name: "Source", requests: [request])
        let target = RequestCollection(name: "Target")
        var workspace = Workspace(collections: [source, target])
        let copied = RequestClipboardPayload(operation: .copy, sourceID: request.id, snapshot: request)
        let first = try XCTUnwrap(RequestOperations.paste(copied, into: target.id, workspace: &workspace))
        let second = try XCTUnwrap(RequestOperations.paste(copied, into: target.id, workspace: &workspace))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(workspace.collections[0].requests.count, 1)
        let cut = RequestClipboardPayload(operation: .cut, sourceID: request.id, snapshot: request)
        XCTAssertEqual(RequestOperations.paste(cut, into: target.id, workspace: &workspace), request.id)
        XCTAssertTrue(workspace.collections[0].requests.isEmpty)
        XCTAssertEqual(workspace.collections[1].requests.count, 3)
    }

    func testPasteAppendsAfterSparseExistingOrders() throws {
        var existing = RequestItem()
        existing.sortOrder = 20
        var incoming = RequestItem()
        incoming.name = "New"
        let collection = RequestCollection(name: "Target", requests: [existing])
        let payload = RequestClipboardPayload(operation: .copy, sourceID: incoming.id, snapshot: incoming)
        var workspace = Workspace(collections: [collection])
        let id = try XCTUnwrap(RequestOperations.paste(payload, into: collection.id, workspace: &workspace))
        XCTAssertEqual(workspace.collections[0].requests.first(where: { $0.id == id })?.sortOrder, 21)
    }
}
