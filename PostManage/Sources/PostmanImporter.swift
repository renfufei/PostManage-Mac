import Foundation

enum PostmanImportError: LocalizedError {
    case invalidJSON
    case unsupportedFormat
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            L10n.string("The file is not valid JSON.", language: L10n.selectedLanguage)
        case .unsupportedFormat:
            L10n.string("This is not a supported Postman Collection (v2.0/v2.1) or Environment export.",
                        language: L10n.selectedLanguage)
        }
    }
}

struct PostmanImportResult {
    var collections: [RequestCollection] = []
    var environments: [Environment] = []
    var warnings: [String] = []
    var requestCount: Int { collections.reduce(0) { $0 + $1.requests.count } }
}

struct PostmanMergeSummary {
    var addedCollections = 0
    var updatedCollections = 0
    var addedRequests = 0
    var updatedRequests = 0
    var addedEnvironments = 0
    var updatedEnvironments = 0
}

enum PostmanImporter {
    static func parse(_ data: Data, fallbackName: String) throws -> PostmanImportResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PostmanImportError.invalidJSON
        }
        if let info = root["info"] as? [String: Any],
           let schema = info["schema"] as? String,
           schema.contains("collection/v2.") || schema.contains("collection/v2.0") {
            let name = nonempty(info["name"] as? String) ?? fallbackName
            let collectionKey = "postman:collection:" + (nonempty(info["_postman_id"] as? String) ?? "name:" + name)
            var result = PostmanImportResult()
            if let unsupported = unsupportedAuth(root["auth"]) {
                result.warnings.append(L10n.format("Collection authorization type '%@' is not supported",
                                                   language: L10n.selectedLanguage, unsupported))
            }
            var collection = RequestCollection(importKey: collectionKey, name: name,
                                               variables: keyValueArray(root["variable"]), folders: [])
            parseItems(root["item"] as? [[String: Any]] ?? [], path: name,
                       sourceKey: collectionKey, parentFolderID: nil,
                       inheritedEvents: root["event"] as? [[String: Any]] ?? [],
                       inheritedAuth: parseAuth(root["auth"]),
                       into: &collection, warnings: &result.warnings)
            result.collections = [collection]
            return result
        }
        if let values = root["values"] as? [[String: Any]],
           root["_postman_variable_scope"] as? String == "environment" {
            var environment = Environment()
            environment.name = nonempty(root["name"] as? String) ?? fallbackName
            environment.importKey = "postman:environment:" + (nonempty(root["id"] as? String) ?? "name:" + environment.name)
            environment.variables = values.compactMap { entry in
                guard let key = nonempty(entry["key"] as? String) else { return nil }
                return KVItem(enabled: entry["enabled"] as? Bool ?? true,
                              key: key, value: stringValue(entry["value"]))
            }
            if environment.variables.isEmpty { environment.variables = [KVItem()] }
            return PostmanImportResult(environments: [environment])
        }
        throw PostmanImportError.unsupportedFormat
    }

    static func merge(_ imported: PostmanImportResult, into workspace: inout Workspace) -> PostmanMergeSummary {
        var summary = PostmanMergeSummary()
        for incoming in imported.collections {
            if let index = workspace.collections.firstIndex(where: {
                ($0.importKey != nil && $0.importKey == incoming.importKey) ||
                ($0.importKey == nil && $0.name == incoming.name)
            }) {
                var current = workspace.collections[index]
                var collectionChanged = current.name != incoming.name || current.importKey != incoming.importKey
                current.name = incoming.name
                current.importKey = incoming.importKey
                if let incomingVariables = incoming.variables {
                    var variables = current.variables ?? []
                    for variable in incomingVariables where !variable.key.isEmpty {
                        if let variableIndex = variables.firstIndex(where: { $0.key == variable.key }) {
                            if variables[variableIndex].enabled != variable.enabled || variables[variableIndex].value != variable.value {
                                var updated = variable
                                updated.id = variables[variableIndex].id
                                variables[variableIndex] = updated
                                collectionChanged = true
                            }
                        } else {
                            variables.append(variable)
                            collectionChanged = true
                        }
                    }
                    current.variables = variables
                }
                var folderIDs: [UUID: UUID] = [:]
                var folders = current.folders ?? []
                for importedFolder in incoming.folders ?? [] {
                    var folder = importedFolder
                    folder.parentID = importedFolder.parentID.flatMap { folderIDs[$0] }
                    if let index = folders.firstIndex(where: {
                        ($0.importKey != nil && $0.importKey == folder.importKey) ||
                        ($0.importKey == nil && $0.parentID == folder.parentID && $0.name == folder.name)
                    }) {
                        let old = folders[index]
                        folder.id = old.id
                        folder.variables = stableItems(folder.variables, old: old.variables)
                        if old != folder { folders[index] = folder; collectionChanged = true }
                    } else {
                        folders.append(folder)
                        collectionChanged = true
                    }
                    folderIDs[importedFolder.id] = folder.id
                }
                current.folders = folders
                for importedRequest in incoming.requests {
                    var request = importedRequest
                    request.folderID = importedRequest.folderID.flatMap { folderIDs[$0] }
                    if let requestIndex = current.requests.firstIndex(where: {
                        ($0.importKey != nil && $0.importKey == request.importKey) ||
                        ($0.importKey == nil && $0.name == request.name && $0.method == request.method)
                    }) {
                        let old = current.requests[requestIndex]
                        if !sameRequest(old, request) || old.importKey != request.importKey {
                            var updated = request
                            updated.id = old.id
                            updated.params = stableItems(request.params, old: old.params)
                            updated.headers = stableItems(request.headers, old: old.headers)
                            updated.form = stableItems(request.form, old: old.form)
                            if let multipart = request.multipart {
                                updated.multipart = stableMultipart(multipart, old: old.multipart ?? [])
                            }
                            current.requests[requestIndex] = updated
                            summary.updatedRequests += 1
                            collectionChanged = true
                        }
                    } else {
                        current.requests.append(request)
                        summary.addedRequests += 1
                        collectionChanged = true
                    }
                }
                if collectionChanged {
                    workspace.collections[index] = current
                    summary.updatedCollections += 1
                }
            } else {
                workspace.collections.append(incoming)
                summary.addedCollections += 1
                summary.addedRequests += incoming.requests.count
            }
        }
        for incoming in imported.environments {
            if let index = workspace.environments.firstIndex(where: {
                ($0.importKey != nil && $0.importKey == incoming.importKey) ||
                ($0.importKey == nil && $0.name == incoming.name)
            }) {
                var current = workspace.environments[index]
                var environmentChanged = current.name != incoming.name || current.importKey != incoming.importKey
                current.name = incoming.name
                current.importKey = incoming.importKey
                for variable in incoming.variables where !variable.key.isEmpty {
                    if let variableIndex = current.variables.firstIndex(where: { $0.key == variable.key }) {
                        if current.variables[variableIndex].enabled != variable.enabled || current.variables[variableIndex].value != variable.value {
                            var updated = variable
                            updated.id = current.variables[variableIndex].id
                            current.variables[variableIndex] = updated
                            environmentChanged = true
                        }
                    } else {
                        current.variables.append(variable)
                        environmentChanged = true
                    }
                }
                if environmentChanged {
                    workspace.environments[index] = current
                    summary.updatedEnvironments += 1
                }
            } else {
                workspace.environments.append(incoming)
                summary.addedEnvironments += 1
            }
        }
        return summary
    }

    private static func sameRequest(_ left: RequestItem, _ right: RequestItem) -> Bool {
        left.name == right.name && left.method == right.method && left.url == right.url &&
        left.folderID == right.folderID && left.sortOrder == right.sortOrder &&
        left.bodyType == right.bodyType && left.body == right.body &&
        left.rawContentType == right.rawContentType && left.binaryPath == right.binaryPath &&
        left.graphqlVariables == right.graphqlVariables &&
        left.auth == right.auth && left.descriptionText == right.descriptionText &&
        left.preScript == right.preScript && left.postScript == right.postScript &&
        sameItems(left.params, right.params) && sameItems(left.headers, right.headers) && sameItems(left.form, right.form) &&
        sameMultipart(left.multipart ?? [], right.multipart ?? [])
    }

    private static func sameItems(_ left: [KVItem], _ right: [KVItem]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { pair in
            pair.0.enabled == pair.1.enabled && pair.0.key == pair.1.key && pair.0.value == pair.1.value
        }
    }

    private static func stableItems(_ incoming: [KVItem], old: [KVItem]) -> [KVItem] {
        var used = Set<UUID>()
        return incoming.map { item in
            var item = item
            if let previous = old.first(where: { $0.key == item.key && !used.contains($0.id) }) {
                item.id = previous.id
                used.insert(previous.id)
            }
            return item
        }
    }

    private static func sameMultipart(_ left: [MultipartPart], _ right: [MultipartPart]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { pair in
            pair.0.enabled == pair.1.enabled && pair.0.key == pair.1.key && pair.0.kind == pair.1.kind &&
            pair.0.value == pair.1.value && pair.0.filePath == pair.1.filePath
        }
    }

    private static func stableMultipart(_ incoming: [MultipartPart], old: [MultipartPart]) -> [MultipartPart] {
        var used = Set<UUID>()
        return incoming.map { part in
            var part = part
            if let previous = old.first(where: { $0.key == part.key && !used.contains($0.id) }) {
                part.id = previous.id
                used.insert(previous.id)
            }
            return part
        }
    }

    private static func parseItems(_ items: [[String: Any]], path: String, sourceKey: String,
                                   parentFolderID: UUID?, inheritedEvents: [[String: Any]],
                                   inheritedAuth: AuthConfig?, into collection: inout RequestCollection,
                                   warnings: inout [String]) {
        for (position, item) in items.enumerated() {
            let requestData = item["request"] as? [String: Any] ??
                (item["request"] as? String).map { ["method": "GET", "url": $0] }
            if let requestData {
                if let unsupported = unsupportedAuth(requestData["auth"]) {
                    warnings.append(L10n.format("%@ / %@: authorization type '%@' is not supported",
                                                language: L10n.selectedLanguage,
                                                path, item["name"] as? String ?? "Request", unsupported))
                }
                if let body = requestData["body"] as? [String: Any], let mode = body["mode"] as? String,
                   !["raw", "urlencoded", "formdata", "file", "graphql"].contains(mode) {
                    warnings.append(L10n.format("%@ / %@: body mode '%@' is not supported",
                                                language: L10n.selectedLanguage,
                                                path, item["name"] as? String ?? "Request", mode))
                }
                var request = parseRequest(item, requestData: requestData, inheritedEvents: inheritedEvents,
                                           inheritedAuth: inheritedAuth)
                request.importKey = sourceKey + "/request:" + (nonempty(item["id"] as? String) ?? "position:" + String(position))
                request.folderID = parentFolderID
                request.sortOrder = position
                collection.requests.append(request)
            } else if let children = item["item"] as? [[String: Any]] {
                let folder = nonempty(item["name"] as? String) ?? "Folder"
                if let unsupported = unsupportedAuth(item["auth"]) {
                    warnings.append(L10n.format("%@ / %@: authorization type '%@' is not supported",
                                                language: L10n.selectedLanguage, path, folder, unsupported))
                }
                let folderEvents = inheritedEvents + (item["event"] as? [[String: Any]] ?? [])
                let folderKey = sourceKey + "/folder:" + (nonempty(item["id"] as? String) ?? "position:" + String(position))
                let folderNode = CollectionFolder(importKey: folderKey, name: folder,
                                                  parentID: parentFolderID, sortOrder: position,
                                                  variables: keyValueArray(item["variable"]))
                collection.folders?.append(folderNode)
                parseItems(children, path: path + " / " + folder, sourceKey: folderKey,
                           parentFolderID: folderNode.id, inheritedEvents: folderEvents,
                           inheritedAuth: parseAuth(item["auth"]) ?? inheritedAuth,
                           into: &collection, warnings: &warnings)
            }
        }
    }

    private static func parseRequest(_ item: [String: Any], requestData: [String: Any],
                                     inheritedEvents: [[String: Any]], inheritedAuth: AuthConfig?) -> RequestItem {
        var request = RequestItem()
        request.name = nonempty(item["name"] as? String) ?? "Imported Request"
        request.method = (requestData["method"] as? String ?? "GET").uppercased()
        request.descriptionText = requestData["description"] as? String
        request.auth = parseAuth(requestData["auth"]) ?? inheritedAuth
        if let rawURL = requestData["url"] as? String {
            request.url = rawURL
        } else if let url = requestData["url"] as? [String: Any] {
            request.url = urlString(url)
            let query = keyValueArray(url["query"])
            if !query.isEmpty {
                request.params = query
                if let question = request.url.firstIndex(of: "?") {
                    request.url = String(request.url[..<question])
                }
            }
        }
        let headers = keyValueArray(requestData["header"])
        if !headers.isEmpty { request.headers = headers }
        if let body = requestData["body"] as? [String: Any] {
            switch body["mode"] as? String {
            case "raw":
                request.bodyType = "raw"
                request.body = body["raw"] as? String ?? ""
                if let options = body["options"] as? [String: Any],
                   let raw = options["raw"] as? [String: Any],
                   let language = raw["language"] as? String {
                    request.rawContentType = contentType(for: language)
                }
            case "urlencoded":
                request.bodyType = "form"
                request.form = keyValueArray(body["urlencoded"])
            case "formdata":
                request.bodyType = "multipart"
                request.multipart = (body["formdata"] as? [[String: Any]] ?? []).compactMap { entry in
                    guard let key = nonempty(entry["key"] as? String) else { return nil }
                    let kind = entry["type"] as? String == "file" ? "file" : "text"
                    let source = entry["src"] as? String ?? (entry["src"] as? [String])?.first ?? ""
                    return MultipartPart(enabled: !(entry["disabled"] as? Bool ?? false), key: key,
                                         kind: kind, value: stringValue(entry["value"]), filePath: source)
                }
            case "file":
                request.bodyType = "binary"
                request.binaryPath = (body["file"] as? [String: Any])?["src"] as? String
            case "graphql":
                request.bodyType = "graphql"
                let graphql = body["graphql"] as? [String: Any] ?? [:]
                request.body = graphql["query"] as? String ?? ""
                request.graphqlVariables = graphql["variables"] as? String ?? ""
            default: break
            }
        }
        let events = inheritedEvents + (item["event"] as? [[String: Any]] ?? [])
        request.preScript = script(events, listen: "prerequest")
        request.postScript = script(events, listen: "test")
        return request
    }

    private static func urlString(_ url: [String: Any]) -> String {
        if let raw = nonempty(url["raw"] as? String) { return raw }
        let scheme = url["protocol"] as? String ?? "https"
        let host = segments(url["host"]).joined(separator: ".")
        let path = segments(url["path"]).joined(separator: "/")
        let port = nonempty(url["port"] as? String).map { ":" + $0 } ?? ""
        return scheme + "://" + host + port + (path.isEmpty ? "" : "/" + path)
    }

    private static func segments(_ value: Any?) -> [String] {
        if let list = value as? [String] { return list }
        if let single = value as? String { return [single] }
        return []
    }

    private static func keyValueArray(_ value: Any?) -> [KVItem] {
        guard let entries = value as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let key = nonempty(entry["key"] as? String) else { return nil }
            return KVItem(enabled: !(entry["disabled"] as? Bool ?? false),
                          key: key, value: stringValue(entry["value"]))
        }
    }

    private static func mergeVariables(_ inherited: [KVItem], _ local: [KVItem]) -> [KVItem] {
        var result = inherited
        for variable in local {
            if let index = result.firstIndex(where: { $0.key == variable.key }) {
                result[index] = variable
            } else {
                result.append(variable)
            }
        }
        return result
    }

    private static func parseAuth(_ value: Any?) -> AuthConfig? {
        guard let object = value as? [String: Any], let type = object["type"] as? String else { return nil }
        var auth = AuthConfig()
        auth.type = type == "noauth" ? "none" : type
        let entries = object[type] as? [[String: Any]] ?? []
        func field(_ name: String) -> String {
            stringValue(entries.first { $0["key"] as? String == name }?["value"])
        }
        switch type {
        case "bearer": auth.token = field("token")
        case "basic":
            auth.username = field("username")
            auth.password = field("password")
        case "apikey":
            auth.key = field("key")
            auth.value = field("value")
            auth.placement = field("in") == "query" ? "query" : "header"
        case "noauth": break
        default: return nil
        }
        return auth
    }

    private static func unsupportedAuth(_ value: Any?) -> String? {
        guard let object = value as? [String: Any], let type = object["type"] as? String else { return nil }
        return ["noauth", "bearer", "basic", "apikey"].contains(type) ? nil : type
    }

    private static func contentType(for language: String) -> String {
        switch language.lowercased() {
        case "json": "application/json"
        case "xml": "application/xml"
        case "html": "text/html"
        case "javascript": "application/javascript"
        default: "text/plain"
        }
    }

    private static func script(_ events: [[String: Any]], listen: String) -> String {
        events.filter { $0["listen"] as? String == listen }
            .compactMap { event -> String? in
                guard let script = event["script"] as? [String: Any] else { return nil }
                if let lines = script["exec"] as? [String] { return lines.joined(separator: "\n") }
                return script["exec"] as? String
            }
            .joined(separator: "\n")
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let text = value as? String { return text }
        return String(describing: value)
    }
}
