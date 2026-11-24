import XCTest
@testable import PostManage

final class IsolatedScriptRunnerTests: XCTestCase {
    func testWorkerRunsAndRedactsSecrets() async throws {
        let result = try await IsolatedScriptRunner.run(
            "console.log(pm.environment.get('apiKey')); console.log('app-key', 'xxx'); pm.environment.set('done', 'yes');",
            variables: ["apiKey": "private-123"])
        XCTAssertEqual(result.variables["done"], "yes")
        XCTAssertEqual(result.logs, ["[REDACTED]", "app-key [REDACTED]"])
    }

    func testInfiniteLoopTimesOut() async throws {
        do {
            _ = try await IsolatedScriptRunner.run("while (true) {}", variables: [:])
            XCTFail("Expected script timeout")
        } catch RequestError.scriptTimeout {
            // Expected: the worker is stopped without blocking the app.
        }
    }
}
