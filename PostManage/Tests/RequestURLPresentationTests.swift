import XCTest
@testable import PostManage

final class RequestURLPresentationTests: XCTestCase {
    func testPreviewIncludesOnlyEnabledParamsWithoutChangingRequest() throws {
        var request = RequestItem()
        request.url = "https://localhost/rc/job/rc/factor/queryRedisValue"
        request.params = [
            KVItem(key: "AWSAccessKeyId", value: "{{AWSAccessKeyId}}"),
            KVItem(key: "Signature", value: "{{Signature}}"),
            KVItem(enabled: false, key: "Ignored", value: "secret")
        ]
        let preview = RequestURLPresentation.urlWithParams(request)
        XCTAssertEqual(preview, "https://localhost/rc/job/rc/factor/queryRedisValue?AWSAccessKeyId={{AWSAccessKeyId}}&Signature={{Signature}}")
        XCTAssertEqual(request.url, "https://localhost/rc/job/rc/factor/queryRedisValue")
        let sent = try RequestEngine.makeURLRequest(request, variables: ["AWSAccessKeyId": "key", "Signature": "sig"])
        XCTAssertEqual(sent.url?.query, "AWSAccessKeyId=key&Signature=sig")
    }

    func testPreviewAppendsBeforeFragmentAndExistingQuery() {
        var request = RequestItem()
        request.url = "https://example.com/path?existing=1#section"
        request.params = [KVItem(key: "next", value: "2")]
        XCTAssertEqual(RequestURLPresentation.urlWithParams(request), "https://example.com/path?existing=1&next=2#section")
    }
}
