import XCTest
@testable import PostManage

final class SearchEngineTests: XCTestCase {
    private func fixture() -> Workspace {
        var first = RequestItem()
        first.name = "Get User"
        first.url = "http://localhost/users"
        first.preScript = "console.log('user user')"
        first.params = [KVItem(key: "userId", value: "user-1")]
        var second = RequestItem()
        second.name = "Get Orders"
        second.url = "http://localhost/orders"
        return Workspace(collections: [
            RequestCollection(name: "User API", requests: [first]),
            RequestCollection(name: "Order API", requests: [second])
        ], environments: [Environment(name: "Local", variables: [KVItem(key: "host", value: "user.local")])])
    }

    func testGlobalAndCollectionScopes() {
        let workspace = fixture()
        let global = SearchEngine.find(in: workspace, query: "user")
        XCTAssertTrue(global.contains { $0.field == "Environment variable value" })
        XCTAssertTrue(global.contains { $0.field == "Pre-request script" && $0.occurrences == 2 })
        let scoped = SearchEngine.find(in: workspace, query: "user", collectionID: workspace.collections[1].id)
        XCTAssertTrue(scoped.isEmpty)
        XCTAssertTrue(SearchEngine.find(in: workspace, query: "USER", caseSensitive: true).isEmpty)
    }

    func testReplaceOneAndAll() throws {
        var workspace = fixture()
        let originalEnvironment = workspace.environments[0].variables[0].value
        let collectionID = workspace.collections[0].id
        let scriptHit = try XCTUnwrap(SearchEngine.find(in: workspace, query: "user", collectionID: collectionID)
            .first { $0.field == "Pre-request script" })
        XCTAssertEqual(SearchEngine.replace(scriptHit, in: &workspace, query: "user", with: "account",
                                            caseSensitive: false, allOccurrences: false), 1)
        XCTAssertEqual(workspace.collections[0].requests[0].preScript, "console.log('account user')")
        let hits = SearchEngine.find(in: workspace, query: "user", collectionID: collectionID)
        let count = SearchEngine.replaceAll(hits, in: &workspace, query: "user", with: "account", caseSensitive: false)
        XCTAssertGreaterThan(count, 1)
        XCTAssertEqual(workspace.collections[0].requests[0].preScript, "console.log('account account')")
        XCTAssertEqual(workspace.environments[0].variables[0].value, originalEnvironment)
        XCTAssertEqual(workspace.collections[1].requests[0].name, "Get Orders")
    }

    func testReplaceEnvironmentVariable() throws {
        var workspace = fixture()
        let hit = try XCTUnwrap(SearchEngine.find(in: workspace, query: "user.local")
            .first { $0.field == "Environment variable value" })
        XCTAssertEqual(SearchEngine.replace(hit, in: &workspace, query: "user.local", with: "api.local",
                                            caseSensitive: true, allOccurrences: false), 1)
        XCTAssertEqual(workspace.environments[0].variables[0].value, "api.local")
    }
}
