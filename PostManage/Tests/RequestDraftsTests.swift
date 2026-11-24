import XCTest
@testable import PostManage

final class RequestDraftsTests: XCTestCase {
    func testRequestEditsStayInDraftOverlayUntilCommitted() {
        var saved = RequestItem()
        saved.url = "http://localhost/saved"
        saved.headers = [KVItem(key: "X-Mode", value: "saved")]
        let workspace = Workspace(collections: [RequestCollection(name: "API", requests: [saved])])
        var draft = saved
        draft.url = "http://localhost/draft"
        draft.headers[0].value = "draft"
        let drafts = [saved.id: draft]

        XCTAssertTrue(RequestDrafts.hasUnsavedChanges(saved.id, drafts: drafts, saved: saved))
        XCTAssertEqual(RequestDrafts.overlay(drafts, on: workspace).collections[0].requests[0], draft)
        XCTAssertEqual(workspace.collections[0].requests[0], saved)
        XCTAssertFalse(RequestDrafts.hasUnsavedChanges(saved.id, drafts: [:], saved: saved))
        XCTAssertFalse(RequestDrafts.hasUnsavedChanges(saved.id, drafts: drafts, saved: draft))
        XCTAssertTrue(RequestDrafts.hasUnsavedChanges(saved.id, drafts: drafts, saved: draft, saveFailed: true))
    }

    func testSearchFindsDraftRequestValues() throws {
        var saved = RequestItem()
        saved.url = "http://localhost/old"
        let workspace = Workspace(collections: [RequestCollection(name: "API", requests: [saved])])
        var draft = saved
        draft.url = "http://localhost/draft"
        var searchable = RequestDrafts.overlay([saved.id: draft], on: workspace)
        let hit = try XCTUnwrap(SearchEngine.find(in: searchable, query: "draft")
            .first(where: { $0.address.kind == "request.url" }))

        XCTAssertEqual(SearchEngine.replace(hit, in: &searchable, query: "draft",
                                            with: "edited", caseSensitive: true,
                                            allOccurrences: false), 1)
        XCTAssertEqual(searchable.collections[0].requests[0].url, "http://localhost/edited")
        XCTAssertEqual(workspace.collections[0].requests[0].url, "http://localhost/old")
    }

    func testImportDoesNotReplaceSavedVersionBehindAnUnsavedDraft() {
        var saved = RequestItem()
        saved.url = "http://localhost/saved"
        let previous = Workspace(collections: [RequestCollection(name: "API", requests: [saved])])
        var draft = saved
        draft.url = "http://localhost/draft"
        var imported = saved
        imported.url = "http://localhost/imported"
        var merged = Workspace(collections: [RequestCollection(name: "API", requests: [imported])])

        XCTAssertEqual(RequestDrafts.preserveUnsavedRequests([saved.id: draft],
                                                              previous: previous, merged: &merged), 1)
        XCTAssertEqual(merged.collections[0].requests[0].url, saved.url)
        XCTAssertEqual(draft.url, "http://localhost/draft")
    }
}
