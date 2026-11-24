import XCTest
@testable import PostManage

final class RequestEngineTests: XCTestCase {
    func testEnvironmentVariablesInURLParamsHeadersAndBody() throws {
        var request = RequestItem()
        request.method = "POST"
        request.url = "https://{{host}}/transfer?source={{envVar}}"
        request.params = [KVItem(key: "account", value: "{{envVar}}")]
        request.headers = [KVItem(key: "X-Account", value: "{{envVar}}")]
        request.bodyType = "raw"
        request.body = #"{"account":"{{envVar}}","quantity":10087}"#
        let prepared = try RequestEngine.makeURLRequest(request, variables: ["host": "example.com", "envVar": "primary"])
        XCTAssertEqual(prepared.url?.absoluteString, "https://example.com/transfer?source=primary&account=primary")
        XCTAssertEqual(prepared.value(forHTTPHeaderField: "X-Account"), "primary")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(prepared.httpBody)) as? [String: Any])
        XCTAssertEqual(body["account"] as? String, "primary")
        XCTAssertEqual(body["quantity"] as? Int, 10087)
    }

    func testPostmanGuidInRawJSONBody() throws {
        var request = RequestItem()
        request.method = "POST"
        request.url = "http://localhost:8080/transfer"
        request.bodyType = "raw"
        request.body = """
        {"reqId":"{{$guid}}","coin":"BTC","userId":57102736,"quantity":10087}
        """
        let first = try RequestEngine.makeURLRequest(request, variables: [:])
        let second = try RequestEngine.makeURLRequest(request, variables: [:])
        let firstBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(first.httpBody)) as? [String: Any])
        let secondBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(second.httpBody)) as? [String: Any])
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(firstBody["reqId"] as? String)))
        XCTAssertNotEqual(firstBody["reqId"] as? String, secondBody["reqId"] as? String)
        XCTAssertEqual(firstBody["coin"] as? String, "BTC")
        XCTAssertEqual(firstBody["userId"] as? Int, 57102736)
        XCTAssertEqual(firstBody["quantity"] as? Int, 10087)
    }

    func testVariablesAndScripts() throws {
        XCTAssertEqual(RequestEngine.interpolate("/{{ key }}/{{missing}}", variables: ["key": "hello"]), "/hello/{{missing}}")
        let result = try RequestEngine.runScript("pm.environment.set('token', 'abc'); console.log(pm.environment.get('token'));", variables: [:])
        XCTAssertEqual(result.variables["token"], "abc")
        XCTAssertEqual(result.logs, ["abc"])
    }

    func testResponseScript() throws {
        let response = ResponseData(status: 200, statusText: "OK", duration: 0.01, size: 11, headers: [], body: "{\"ok\":true}")
        let result = try RequestEngine.runScript("pm.test('status', function() { pm.expect(pm.response.code).to.eql(200); }); pm.environment.set('ok', pm.response.json().ok);", variables: [:], response: response)
        XCTAssertEqual(result.logs, ["PASS status"])
        XCTAssertEqual(result.variables["ok"], "true")
    }

    func testCryptoJSHmacSHA256Base64KnownVector() throws {
        let script = """
        var bytes = CryptoJS.HmacSHA256('The quick brown fox jumps over the lazy dog', 'key');
        pm.environment.set('signature', CryptoJS.enc.Base64.stringify(bytes));
        """
        let result = try RequestEngine.runScript(script, variables: [:])
        XCTAssertEqual(result.variables["signature"], "97yD9DBThCSxMpjmqm+xQ+9NWaFJRhdZl0edvC0aPNg=")
    }

    func testPostmanRequestFieldsForPreScript() throws {
        var request = RequestItem()
        request.method = "GET"
        request.url = "https://{{host}}:8443/v1/users?raw=1"
        request.params = [KVItem(key: "active", value: "yes"), KVItem(enabled: false, key: "ignored", value: "no")]
        let script = """
        var members = pm.request.url.query.members;
        pm.environment.set('method', pm.request.method);
        pm.environment.set('path', '/' + pm.request.url.path.join('/'));
        pm.environment.set('port', pm.request.url.port);
        pm.environment.set('keys', members.filter(function(x) { return !x.disabled; }).map(function(x) { return x.key; }).join(','));
        pm.environment.set('stamp', new Date().toISOString().slice(0, 19));
        """
        let result = try RequestEngine.runScript(script, variables: ["host": "example.com"], request: request)
        XCTAssertEqual(result.variables["method"], "GET")
        XCTAssertEqual(result.variables["path"], "/v1/users")
        XCTAssertEqual(result.variables["port"], "8443")
        XCTAssertEqual(result.variables["keys"], "raw,active")
        XCTAssertEqual(result.variables["stamp"]?.count, 19)
    }

    func testPreEncodedSignatureIsNotDoubleEncoded() throws {
        var request = RequestItem()
        request.url = "https://example.com/api"
        request.params = [KVItem(key: "Signature", value: "{{Signature}}")]
        let prepared = try RequestEngine.makeURLRequest(request, variables: ["Signature": "abc%2Fdef%2Bghi%3D"])
        XCTAssertEqual(prepared.url?.absoluteString, "https://example.com/api?Signature=abc%2Fdef%2Bghi%3D")
    }

    func testProvidedStyleSignaturePreScript() throws {
        var request = RequestItem()
        request.method = "GET"
        request.url = "https://{{host}}/v1/orders"
        request.params = [KVItem(key: "symbol", value: "BTC"), KVItem(enabled: false, key: "ignored", value: "x")]
        let script = """
        var awsAccessKeyId = "xxx" || pm.environment.get("app-id");
        var awsAccessKeySecret = "xxx" || pm.environment.get("app-key");
        var signatureVersion = 2;
        var signatureMethod = "HmacSHA256";
        var timestamp = new Date().toISOString().slice(0, 19);
        var requestMethod = pm.request.method;
        var queryParam = pm.request.url.query.members;
        var host = pm.environment.get("host") || "example.com";
        var path = "/" + pm.request.url.path.join("/");
        var queryList = {
            values: [],
            sigkey: ["AWSAccessKeyId", "SignatureVersion", "SignatureMethod", "Timestamp", "Signature"],
            put: function(k, v) {
                var index = -1;
                for (var i = 0; i < this.values.length; i++) {
                    var key = this.values[i].split("=")[0];
                    if (key == k) { index = -1; break; }
                }
                var value = encodeURIComponent(v);
                if (index == -1) this.values.push(k + "=" + value);
                else this.values[index] = k + "=" + value;
            },
            sortedValues: function() { console.log(this.values); return this.values.sort(); },
            inSigkey: function(k) {
                for (var i = 0; i < this.sigkey.length; i++) if (k == this.sigkey[i]) return true;
                return false;
            }
        };
        for (var i = 0; i < queryParam.length; i++) {
            if (queryParam[i].disabled || queryList.inSigkey(queryParam[i].key)) continue;
            queryList.put(queryParam[i].key, queryParam[i].value);
        }
        queryList.put("Timestamp", timestamp);
        queryList.put("AWSAccessKeyId", awsAccessKeyId);
        queryList.put("SignatureMethod", signatureMethod);
        queryList.put("SignatureVersion", signatureVersion);
        var payload = requestMethod.toUpperCase() + "\\n" + host.toLowerCase() + "\\n" + path + "\\n" + queryList.sortedValues().join("&");
        var signatureBytes = CryptoJS.HmacSHA256(payload, awsAccessKeySecret);
        var signature = CryptoJS.enc.Base64.stringify(signatureBytes);
        pm.environment.set("AWSAccessKeyId", awsAccessKeyId);
        pm.environment.set("SignatureVersion", signatureVersion);
        pm.environment.set("SignatureMethod", signatureMethod);
        pm.environment.set("Timestamp", timestamp);
        pm.environment.set("Signature", encodeURIComponent(signature));
        console.log("request", pm.request);
        console.log("signature", signature);
        console.log(payload);
        """
        let result = try RequestEngine.runScript(script, variables: ["host": "example.com"], request: request)
        XCTAssertEqual(result.variables["AWSAccessKeyId"], "xxx")
        XCTAssertEqual(result.variables["SignatureMethod"], "HmacSHA256")
        XCTAssertFalse(try XCTUnwrap(result.variables["Signature"]).isEmpty)
        XCTAssertTrue(result.logs.contains { $0.contains("symbol=BTC") })
        XCTAssertFalse(result.logs.contains { $0.contains("ignored=x") })
    }

    func testAuthAndMultipartRequest() throws {
        var request = RequestItem()
        request.method = "POST"
        request.url = "http://localhost/upload"
        request.auth = AuthConfig(type: "bearer", token: "{{token}}")
        request.bodyType = "multipart"
        request.multipart = [MultipartPart(key: "note", value: "hello")]
        let prepared = try RequestEngine.makeURLRequest(request, variables: ["token": "abc"])
        XCTAssertEqual(prepared.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertTrue(try XCTUnwrap(prepared.value(forHTTPHeaderField: "Content-Type")).hasPrefix("multipart/form-data; boundary="))
        XCTAssertTrue(String(decoding: try XCTUnwrap(prepared.httpBody), as: UTF8.self).contains("hello"))

        request.auth = AuthConfig(type: "apikey", key: "api_key", value: "{{token}}", placement: "query")
        let apiKeyRequest = try RequestEngine.makeURLRequest(request, variables: ["token": "abc"])
        XCTAssertEqual(apiKeyRequest.url?.query, "api_key=abc")

        request.auth = AuthConfig(type: "basic", username: "user", password: "pass")
        let basicRequest = try RequestEngine.makeURLRequest(request, variables: [:])
        XCTAssertEqual(basicRequest.value(forHTTPHeaderField: "Authorization"), "Basic dXNlcjpwYXNz")
    }

    func testGraphQLAndBinaryBodies() throws {
        var request = RequestItem()
        request.method = "POST"
        request.url = "http://localhost/graphql"
        request.bodyType = "graphql"
        request.body = "query { user(id: $id) { name } }"
        request.graphqlVariables = "{\"id\": 42}"
        let prepared = try RequestEngine.makeURLRequest(request, variables: [:])
        let body = try XCTUnwrap(prepared.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((object["variables"] as? [String: Int])?["id"], 42)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([0, 1, 2, 255]).write(to: file)
        request.bodyType = "binary"
        request.binaryPath = file.path
        XCTAssertEqual(try RequestEngine.makeURLRequest(request, variables: [:]).httpBody, Data([0, 1, 2, 255]))
    }
}
