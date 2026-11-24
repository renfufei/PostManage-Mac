import XCTest
@testable import PostManage

final class CollectionOrganizerTests: XCTestCase {
    func testMoveAndReorderRequests() throws {
        let folder = CollectionFolder(name: "Users")
        var first = RequestItem()
        first.name = "A"
        first.sortOrder = 0
        var second = RequestItem()
        second.name = "B"
        second.sortOrder = 1
        var collection = RequestCollection(name: "API", requests: [first, second], folders: [folder])
        XCTAssertTrue(CollectionOrganizer.move("request:\(second.id)", in: &collection, to: nil, before: first.id))
        XCTAssertLessThan(try XCTUnwrap(collection.requests.first { $0.id == second.id }?.sortOrder),
                          try XCTUnwrap(collection.requests.first { $0.id == first.id }?.sortOrder))
        XCTAssertTrue(CollectionOrganizer.move("request:\(first.id)", in: &collection, to: folder.id))
        XCTAssertEqual(collection.requests.first { $0.id == first.id }?.folderID, folder.id)
    }

    func testFolderCannotMoveInsideItselfOrChild() {
        let parent = CollectionFolder(name: "Parent")
        let child = CollectionFolder(name: "Child", parentID: parent.id)
        var collection = RequestCollection(name: "API", folders: [parent, child])
        XCTAssertFalse(CollectionOrganizer.move("folder:\(parent.id)", in: &collection, to: child.id))
        XCTAssertEqual(collection.folders?.first { $0.id == parent.id }?.parentID, nil)
    }
}
