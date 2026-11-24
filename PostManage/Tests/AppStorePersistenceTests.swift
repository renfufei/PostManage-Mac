import XCTest
@testable import PostManage

@MainActor final class AppStorePersistenceTests: XCTestCase {
    func testUnreadableWorkspaceIsPreservedUntilExplicitRecovery() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostManagePersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        let original = Data("{broken json".utf8)
        try original.write(to: workspaceURL)

        let store = AppStore(directory: directory)
        XCTAssertNotNil(store.workspaceLoadError)
        store.workspace.collections[0].name = "Edited in memory"
        XCTAssertEqual(try Data(contentsOf: workspaceURL), original)

        let backup = try XCTUnwrap(store.recoverUnreadableWorkspace())
        XCTAssertEqual(try Data(contentsOf: backup), original)
        let recovered = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: workspaceURL))
        XCTAssertEqual(recovered.collections[0].name, "Edited in memory")
        XCTAssertNil(store.workspaceLoadError)
        XCTAssertNil(store.saveError)
    }

    func testRequestDraftUsesEditedValuesWithoutWritingUntilSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostManageDraftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AppStore(directory: directory)
        store.retrySave()
        let workspaceURL = directory.appendingPathComponent("workspace.json")
        let persistedBefore = try Data(contentsOf: workspaceURL)
        let requestID = try XCTUnwrap(store.workspace.collections.first?.requests.first?.id)
        var draft = try XCTUnwrap(store.request(requestID))
        draft.url = "http://localhost:9876/draft"
        draft.headers = [KVItem(key: "X-Draft", value: "yes")]
        store.requestDrafts[requestID] = draft

        XCTAssertTrue(store.requestHasUnsavedChanges(requestID))
        XCTAssertEqual(try Data(contentsOf: workspaceURL), persistedBefore)
        XCTAssertEqual(try RequestEngine.makeURLRequest(draft, variables: [:]).url?.absoluteString,
                       "http://localhost:9876/draft")

        XCTAssertTrue(store.saveRequestDraft(requestID))
        XCTAssertFalse(store.requestHasUnsavedChanges(requestID))
        let persisted = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: workspaceURL))
        XCTAssertEqual(persisted.collections[0].requests[0].url, draft.url)
        XCTAssertEqual(persisted.collections[0].requests[0].headers[0].value, "yes")
    }
}
