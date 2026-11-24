import Foundation
import JavaScriptCore
import CryptoKit

struct ScriptResult {
    var variables: [String: String]
    var logs: [String]
}

enum RequestError: LocalizedError {
    case invalidURL(String)
    case script(String)
    case scriptTimeout(Int)
    case missingFile(String)
    case invalidBody(String)
    var errorDescription: String? {
        let language = L10n.selectedLanguage
        switch self {
        case .invalidURL(let value):
            return L10n.format("Invalid URL: %@", language: language, value)
        case .script(let value):
            return L10n.format("Script error: %@", language: language, value)
        case .scriptTimeout(let seconds):
            return L10n.format("Script exceeded the %d-second limit", language: language, seconds)
        case .missingFile(let value):
            return L10n.format("Request file not found: %@", language: language, value)
        case .invalidBody(let value):
            return L10n.format("Invalid request body: %@", language: language, value)
        }
    }
}

enum RequestEngine {
    static func interpolate(_ input: String, variables: [String: String]) -> String {
        let regex = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
        var output = input
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed() {
            guard let full = Range(match.range, in: input), let keyRange = Range(match.range(at: 1), in: input) else { continue }
            let key = String(input[keyRange]).trimmingCharacters(in: .whitespaces)
            if key == "$guid" {
                output.replaceSubrange(full, with: UUID().uuidString.lowercased())
            } else if let value = variables[key] {
                output.replaceSubrange(full, with: value)
            }
        }
        return output
    }

    static func runScript(_ script: String, variables: [String: String], response: ResponseData? = nil,
                          request: RequestItem? = nil) throws -> ScriptResult {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ScriptResult(variables: variables, logs: [])
        }
        let context = JSContext()!
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() ?? "Unknown JavaScript error" }
        let json = try String(data: JSONSerialization.data(withJSONObject: variables), encoding: .utf8)!
        let responseBody = try String(data: JSONSerialization.data(withJSONObject: response?.body ?? "", options: [.fragmentsAllowed]), encoding: .utf8)!
        let requestJSON = try String(data: JSONSerialization.data(withJSONObject: scriptRequest(request, variables: variables)), encoding: .utf8)!
        let status = response?.status ?? 0
        let hmacSHA256: @convention(block) (String, String) -> String = { message, secret in
            let key = SymmetricKey(data: Data(secret.utf8))
            let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
            return Data(signature).base64EncodedString()
        }
        context.setObject(hmacSHA256, forKeyedSubscript: "__nativeHmacSHA256" as NSString)
        let bootstrap = """
        var __values = \(json);
        var __logs = [];
        var __request = \(requestJSON);
        var pm = {
          environment: { get: function(k) { return __values[k]; }, set: function(k,v) { __values[k] = String(v); }, unset: function(k) { delete __values[k]; } },
          variables: { get: function(k) { return __values[k]; }, set: function(k,v) { __values[k] = String(v); } },
          request: __request,
          response: { code: \(status), text: function() { return \(responseBody); }, json: function() { return JSON.parse(\(responseBody)); } },
          test: function(name, fn) { try { fn(); __logs.push('PASS ' + name); } catch(e) { __logs.push('FAIL ' + name + ': ' + e); } },
          expect: function(value) { return { to: { eql: function(expected) { if (JSON.stringify(value) !== JSON.stringify(expected)) throw Error('expected ' + JSON.stringify(expected) + ', got ' + JSON.stringify(value)); } } }; }
        };
        var CryptoJS = {
          HmacSHA256: function(message, secret) { return { __base64: __nativeHmacSHA256(String(message), String(secret)) }; },
          enc: { Base64: { stringify: function(bytes) { return bytes.__base64; } } }
        };
        var console = { log: function() { __logs.push(Array.prototype.join.call(arguments, ' ')); } };
        """
        context.evaluateScript(bootstrap)
        if let exception { throw RequestError.script(exception) }
        context.evaluateScript(script)
        if let exception { throw RequestError.script(exception) }
        guard let result = context.evaluateScript("JSON.stringify({ values: __values, logs: __logs })")?.toString(),
              let data = result.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RequestError.script("Could not read script result")
        }
        return ScriptResult(variables: object["values"] as? [String: String] ?? variables,
                            logs: object["logs"] as? [String] ?? [])
    }

    private static func scriptRequest(_ item: RequestItem?, variables: [String: String]) -> [String: Any] {
        guard let item else {
            return ["method": "", "url": ["raw": "", "path": [], "host": "", "port": NSNull(), "query": ["members": []]]]
        }
        let urlText = interpolate(item.url, variables: variables)
        let components = URLComponents(string: urlText)
        var members: [[String: Any]] = (components?.queryItems ?? []).map {
            ["key": $0.name, "value": $0.value ?? "", "disabled": false]
        }
        members += item.params.filter { !$0.key.isEmpty }.map {
            ["key": interpolate($0.key, variables: variables),
             "value": interpolate($0.value, variables: variables),
             "disabled": !$0.enabled] as [String: Any]
        }
        let path = (components?.path ?? "").split(separator: "/").map(String.init)
        return [
            "method": item.method,
            "url": [
                "raw": urlText,
                "host": components?.host ?? "",
                "port": components?.port.map { $0 as Any } ?? NSNull(),
                "path": path,
                "query": ["members": members]
            ]
        ]
    }

    static func makeURLRequest(_ item: RequestItem, variables: [String: String]) throws -> URLRequest {
        let urlText = interpolate(item.url, variables: variables)
        guard var components = URLComponents(string: urlText) else { throw RequestError.invalidURL(urlText) }
        var newQuery = item.params.filter { $0.enabled && !$0.key.isEmpty }.map {
            percentEncodeQueryComponent(interpolate($0.key, variables: variables)) + "=" +
            percentEncodeQueryComponent(interpolate($0.value, variables: variables))
        }
        if let auth = item.auth, auth.type == "apikey", auth.placement == "query", !auth.key.isEmpty {
            newQuery.append(percentEncodeQueryComponent(interpolate(auth.key, variables: variables)) + "=" +
                            percentEncodeQueryComponent(interpolate(auth.value, variables: variables)))
        }
        if !newQuery.isEmpty {
            components.percentEncodedQuery = ([components.percentEncodedQuery].compactMap { $0 }.filter { !$0.isEmpty } + newQuery).joined(separator: "&")
        }
        guard let url = components.url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            throw RequestError.invalidURL(urlText)
        }
        var request = URLRequest(url: url)
        request.httpMethod = item.method
        request.timeoutInterval = 60
        for header in item.headers where header.enabled && !header.key.isEmpty {
            request.setValue(interpolate(header.value, variables: variables), forHTTPHeaderField: interpolate(header.key, variables: variables))
        }
        if let auth = item.auth {
            switch auth.type {
            case "bearer":
                if request.value(forHTTPHeaderField: "Authorization") == nil {
                    request.setValue("Bearer " + interpolate(auth.token, variables: variables), forHTTPHeaderField: "Authorization")
                }
            case "basic":
                if request.value(forHTTPHeaderField: "Authorization") == nil {
                    let credential = interpolate(auth.username, variables: variables) + ":" + interpolate(auth.password, variables: variables)
                    request.setValue("Basic " + Data(credential.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
                }
            case "apikey":
                let key = interpolate(auth.key, variables: variables)
                if auth.placement == "header" && !key.isEmpty && request.value(forHTTPHeaderField: key) == nil {
                    request.setValue(interpolate(auth.value, variables: variables), forHTTPHeaderField: key)
                }
            default: break
            }
        }
        if item.bodyType == "raw" {
            request.httpBody = interpolate(item.body, variables: variables).data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue(item.rawContentType ?? "application/json", forHTTPHeaderField: "Content-Type") }
        } else if item.bodyType == "form" {
            var form = URLComponents()
            form.queryItems = item.form.filter { $0.enabled && !$0.key.isEmpty }.map {
                URLQueryItem(name: interpolate($0.key, variables: variables), value: interpolate($0.value, variables: variables))
            }
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        } else if item.bodyType == "multipart" {
            let boundary = "PostManage-" + UUID().uuidString
            var body = Data()
            for part in item.multipart ?? [] where part.enabled && !part.key.isEmpty {
                let name = interpolate(part.key, variables: variables).replacingOccurrences(of: "\"", with: "\\\"")
                body.append(Data("--\(boundary)\r\n".utf8))
                if part.kind == "file" {
                    let path = (interpolate(part.filePath, variables: variables) as NSString).expandingTildeInPath
                    guard FileManager.default.fileExists(atPath: path) else { throw RequestError.missingFile(path) }
                    let filename = URL(fileURLWithPath: path).lastPathComponent.replacingOccurrences(of: "\"", with: "\\\"")
                    body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
                    body.append(try Data(contentsOf: URL(fileURLWithPath: path)))
                } else {
                    body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
                    body.append(Data(interpolate(part.value, variables: variables).utf8))
                }
                body.append(Data("\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            request.httpBody = body
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        } else if item.bodyType == "binary" {
            let path = (interpolate(item.binaryPath ?? "", variables: variables) as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { throw RequestError.missingFile(path) }
            request.httpBody = try Data(contentsOf: URL(fileURLWithPath: path))
            if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type") }
        } else if item.bodyType == "graphql" {
            let variablesText = interpolate(item.graphqlVariables ?? "", variables: variables)
            var payload: [String: Any] = ["query": interpolate(item.body, variables: variables)]
            if !variablesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let data = variablesText.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) else {
                    throw RequestError.invalidBody("GraphQL variables must be valid JSON")
                }
                payload["variables"] = object
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        }
        return request
    }

    private static func percentEncodeQueryComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        let regex = try! NSRegularExpression(pattern: "%25([0-9A-Fa-f]{2})")
        return regex.stringByReplacingMatches(in: encoded, range: NSRange(encoded.startIndex..., in: encoded), withTemplate: "%$1")
    }

    static func send(_ item: RequestItem, variables: [String: String]) async throws -> ResponseData {
        let request = try makeURLRequest(item, variables: variables)
        let started = Date()
        let trace = ResponseTrace()
        let (data, response) = try await URLSession.shared.data(for: request, delegate: trace)
        guard let http = response as? HTTPURLResponse else { throw RequestError.invalidURL("Non-HTTP response") }
        let headers = http.allHeaderFields.map { (String(describing: $0.key), String(describing: $0.value)) }.sorted { $0.0.lowercased() < $1.0.lowercased() }
        let headerFields = Dictionary(uniqueKeysWithValues: headers)
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: http.url ?? request.url!).map {
            ResponseCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path)
        }
        return ResponseData(status: http.statusCode, statusText: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                            duration: Date().timeIntervalSince(started), size: data.count, headers: headers,
                            body: String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self),
                            rawData: data, mimeType: http.mimeType, finalURL: http.url?.absoluteString,
                            cookies: cookies, redirects: trace.redirects, timings: trace.timings)
    }
}
