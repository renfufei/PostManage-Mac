import Foundation

enum PostmanExporter {
    static func export(_ collection: RequestCollection) throws -> Data {
        var root: [String: Any] = [
            "info": [
                "name": collection.name,
                "_postman_id": collection.importKey?.replacingOccurrences(of: "postman:collection:", with: "") ?? collection.id.uuidString,
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": exportItems(collection, parentID: nil)
        ]
        if let variables = collection.variables, !variables.isEmpty {
            root["variable"] = variables.filter { !$0.key.isEmpty }.map {
                ["key": $0.key, "value": $0.value, "disabled": !$0.enabled] as [String: Any]
            }
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private static func exportItems(_ collection: RequestCollection, parentID: UUID?) -> [[String: Any]] {
        var entries: [(Int, [String: Any])] = []
        for (position, request) in collection.requests.enumerated() where request.folderID == parentID {
            entries.append((request.sortOrder ?? position, exportRequest(request)))
        }
        for folder in collection.folders ?? [] where folder.parentID == parentID {
            let sourceID = folder.importKey?.components(separatedBy: "/folder:").last ?? folder.id.uuidString
            var object: [String: Any] = [
                "id": sourceID,
                "name": folder.name,
                "item": exportItems(collection, parentID: folder.id)
            ]
            if !folder.variables.isEmpty {
                object["variable"] = folder.variables.filter { !$0.key.isEmpty }.map(exportKV)
            }
            entries.append((folder.sortOrder, object))
        }
        return entries.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func exportRequest(_ item: RequestItem) -> [String: Any] {
        var request: [String: Any] = [
            "method": item.method,
            "url": exportURL(item),
            "header": item.headers.filter { !$0.key.isEmpty }.map(exportKV)
        ]
        if let description = item.descriptionText, !description.isEmpty {
            request["description"] = description
        }
        if let auth = item.auth, let object = exportAuth(auth) {
            request["auth"] = object
        }
        switch item.bodyType {
        case "raw":
            var body: [String: Any] = ["mode": "raw", "raw": item.body]
            if let contentType = item.rawContentType {
                let language: String
                switch contentType {
                case "application/json": language = "json"
                case "application/xml": language = "xml"
                case "text/html": language = "html"
                case "application/javascript": language = "javascript"
                default: language = "text"
                }
                body["options"] = ["raw": ["language": language]]
            }
            request["body"] = body
        case "form":
            request["body"] = ["mode": "urlencoded", "urlencoded": item.form.filter { !$0.key.isEmpty }.map(exportKV)] as [String: Any]
        case "multipart":
            request["body"] = ["mode": "formdata", "formdata": (item.multipart ?? []).filter { !$0.key.isEmpty }.map { part -> [String: Any] in
                var object: [String: Any] = ["key": part.key, "type": part.kind, "disabled": !part.enabled]
                if part.kind == "file" { object["src"] = part.filePath }
                else { object["value"] = part.value }
                return object
            }] as [String: Any]
        case "binary":
            request["body"] = ["mode": "file", "file": ["src": item.binaryPath ?? ""]] as [String: Any]
        case "graphql":
            request["body"] = ["mode": "graphql", "graphql": ["query": item.body, "variables": item.graphqlVariables ?? ""]] as [String: Any]
        default: break
        }
        var events: [[String: Any]] = []
        if !item.preScript.isEmpty {
            events.append(["listen": "prerequest", "script": ["type": "text/javascript", "exec": item.preScript.components(separatedBy: "\n")]])
        }
        if !item.postScript.isEmpty {
            events.append(["listen": "test", "script": ["type": "text/javascript", "exec": item.postScript.components(separatedBy: "\n")]])
        }
        let sourceID = item.importKey?.components(separatedBy: "/request:").last ?? item.id.uuidString
        var result: [String: Any] = ["id": sourceID, "name": item.name, "request": request]
        if !events.isEmpty { result["event"] = events }
        return result
    }

    private static func exportURL(_ item: RequestItem) -> [String: Any] {
        let params = item.params.filter { !$0.key.isEmpty }
        let enabled = params.filter(\.enabled)
        let suffix = enabled.map { $0.key + "=" + $0.value }.joined(separator: "&")
        let raw = item.url + (suffix.isEmpty ? "" : (item.url.contains("?") ? "&" : "?") + suffix)
        let existingQuery: [KVItem]
        if !params.isEmpty, let query = item.url.split(separator: "?", maxSplits: 1).dropFirst().first {
            existingQuery = query.split(separator: "&").map { pair in
                let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                return KVItem(key: String(pieces[0]).removingPercentEncoding ?? String(pieces[0]),
                              value: pieces.count > 1 ? (String(pieces[1]).removingPercentEncoding ?? String(pieces[1])) : "")
            }
        } else {
            existingQuery = []
        }
        return [
            "raw": raw,
            "query": (existingQuery + params).map(exportKV)
        ]
    }

    private static func exportKV(_ item: KVItem) -> [String: Any] {
        ["key": item.key, "value": item.value, "disabled": !item.enabled]
    }

    private static func exportAuth(_ auth: AuthConfig) -> [String: Any]? {
        switch auth.type {
        case "none": return ["type": "noauth"]
        case "bearer": return ["type": "bearer", "bearer": [["key": "token", "value": auth.token, "type": "string"]]]
        case "basic": return ["type": "basic", "basic": [
            ["key": "username", "value": auth.username, "type": "string"],
            ["key": "password", "value": auth.password, "type": "string"]
        ]]
        case "apikey": return ["type": "apikey", "apikey": [
            ["key": "key", "value": auth.key, "type": "string"],
            ["key": "value", "value": auth.value, "type": "string"],
            ["key": "in", "value": auth.placement, "type": "string"]
        ]]
        default: return nil
        }
    }
}
