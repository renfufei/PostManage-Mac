import XCTest
@testable import PostManage

final class EditorTabsTests: XCTestCase {
    func testRequestAndEnvironmentShareOneClosableTabList() {
        let request = RequestItem()
        let environment = Environment()
        let requestTab = EditorTab.request(request.id)
        let environmentTab = EditorTab.environment(environment.id)

        let opened = EditorTabs.opening(environmentTab,
                                        in: EditorTabs.opening(requestTab, in: []))
        XCTAssertEqual(opened, [requestTab, environmentTab])
        XCTAssertEqual(EditorTabs.opening(environmentTab, in: opened), opened)
        XCTAssertEqual(EditorTabs.closing(environmentTab, in: opened).last, requestTab)

        let workspace = Workspace(collections: [RequestCollection(requests: [])],
                                  environments: [environment])
        XCTAssertEqual(EditorTabs.available(opened, in: workspace), [environmentTab])
    }
}
