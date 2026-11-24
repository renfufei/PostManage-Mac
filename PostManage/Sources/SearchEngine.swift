import Foundation

struct SearchAddress: Hashable {
    var collectionID: UUID?
    var requestID: UUID?
    var folderID: UUID?
    var environmentID: UUID?
    var rowID: UUID?
    var kind: String
}

struct SearchHit: Identifiable {
    var id: SearchAddress { address }
    let address: SearchAddress
    let context: String
    let field: String
    let text: String
    let occurrences: Int

    var preview: String {
        if field == "Auth password" { return "••••••" }
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        return String(flattened.prefix(180))
    }
}

enum SearchEngine {
    static func find(in workspace: Workspace, query: String, collectionID: UUID? = nil,
                     caseSensitive: Bool = false) -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        var hits: [SearchHit] = []
        func append(_ text: String, _ context: String, _ field: String, _ address: SearchAddress) {
            let count = occurrences(in: text, query: query, caseSensitive: caseSensitive)
            if count > 0 {
                hits.append(SearchHit(address: address, context: context, field: field,
                                      text: text, occurrences: count))
            }
        }
        for collection in workspace.collections where collectionID == nil || collection.id == collectionID {
            let base = SearchAddress(collectionID: collection.id, kind: "collection.name")
            append(collection.name, collection.name, "Collection name", base)
            for variable in collection.variables ?? [] {
                let address = SearchAddress(collectionID: collection.id, rowID: variable.id, kind: "collection.variable.key")
                append(variable.key, collection.name, "Collection variable key", address)
                append(variable.value, collection.name, "Collection variable value",
                       SearchAddress(collectionID: collection.id, rowID: variable.id, kind: "collection.variable.value"))
            }
            for folder in collection.folders ?? [] {
                let context = collection.name + " / " + collection.folderPath(for: folder.id)
                append(folder.name, context, "Folder name",
                       SearchAddress(collectionID: collection.id, folderID: folder.id, kind: "folder.name"))
                for variable in folder.variables {
                    append(variable.key, context, "Folder variable key",
                           SearchAddress(collectionID: collection.id, folderID: folder.id,
                                         rowID: variable.id, kind: "folder.variable.key"))
                    append(variable.value, context, "Folder variable value",
                           SearchAddress(collectionID: collection.id, folderID: folder.id,
                                         rowID: variable.id, kind: "folder.variable.value"))
                }
            }
            for request in collection.requests {
                let folderPath = collection.folderPath(for: request)
                let context = collection.name + (folderPath.isEmpty ? "" : " / " + folderPath) + " / " + request.name
                func requestAddress(_ kind: String, rowID: UUID? = nil) -> SearchAddress {
                    SearchAddress(collectionID: collection.id, requestID: request.id, rowID: rowID, kind: kind)
                }
                append(request.name, context, "Request name", requestAddress("request.name"))
                append(request.url, context, "URL", requestAddress("request.url"))
                append(request.descriptionText ?? "", context, "Description", requestAddress("request.description"))
                append(request.body, context, "Body", requestAddress("request.body"))
                append(request.binaryPath ?? "", context, "Binary file path", requestAddress("request.binaryPath"))
                append(request.graphqlVariables ?? "", context, "GraphQL variables", requestAddress("request.graphqlVariables"))
                append(request.preScript, context, "Pre-request script", requestAddress("request.preScript"))
                append(request.postScript, context, "Post-response script", requestAddress("request.postScript"))
                for (label, items, prefix) in [
                    ("Parameter", request.params, "request.param"),
                    ("Header", request.headers, "request.header"),
                    ("Form field", request.form, "request.form")
                ] {
                    for item in items {
                        append(item.key, context, label + " key", requestAddress(prefix + ".key", rowID: item.id))
                        append(item.value, context, label + " value", requestAddress(prefix + ".value", rowID: item.id))
                    }
                }
                for part in request.multipart ?? [] {
                    append(part.key, context, "Multipart key", requestAddress("request.multipart.key", rowID: part.id))
                    append(part.value, context, "Multipart value", requestAddress("request.multipart.value", rowID: part.id))
                    append(part.filePath, context, "Multipart file path", requestAddress("request.multipart.filePath", rowID: part.id))
                }
                if let auth = request.auth {
                    for (label, value, kind) in [
                        ("Auth token", auth.token, "token"),
                        ("Auth username", auth.username, "username"),
                        ("Auth password", auth.password, "password"),
                        ("API key name", auth.key, "key"),
                        ("API key value", auth.value, "value")
                    ] {
                        append(value, context, label, requestAddress("request.auth." + kind))
                    }
                }
            }
        }
        if collectionID == nil {
            for environment in workspace.environments {
                append(environment.name, environment.name, "Environment name",
                       SearchAddress(environmentID: environment.id, kind: "environment.name"))
                for variable in environment.variables {
                    append(variable.key, environment.name, "Environment variable key",
                           SearchAddress(environmentID: environment.id, rowID: variable.id, kind: "environment.variable.key"))
                    append(variable.value, environment.name, "Environment variable value",
                           SearchAddress(environmentID: environment.id, rowID: variable.id, kind: "environment.variable.value"))
                }
            }
        }
        return hits
    }

    static func replace(_ hit: SearchHit, in workspace: inout Workspace, query: String,
                        with replacement: String, caseSensitive: Bool, allOccurrences: Bool) -> Int {
        guard !query.isEmpty else { return 0 }
        var replaced = 0
        func changed(_ original: String) -> String {
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            if allOccurrences {
                replaced = occurrences(in: original, query: query, caseSensitive: caseSensitive)
                return original.replacingOccurrences(of: query, with: replacement, options: options)
            }
            guard let range = original.range(of: query, options: options) else { return original }
            replaced = 1
            var output = original
            output.replaceSubrange(range, with: replacement)
            return output
        }
        let address = hit.address
        if let collectionID = address.collectionID,
           let ci = workspace.collections.firstIndex(where: { $0.id == collectionID }) {
            if address.kind == "collection.name" {
                workspace.collections[ci].name = changed(workspace.collections[ci].name)
            } else if address.kind.hasPrefix("collection.variable.") {
                var values = workspace.collections[ci].variables ?? []
                mutateKV(&values, rowID: address.rowID, kind: address.kind, transform: changed)
                workspace.collections[ci].variables = values
            } else if let folderID = address.folderID,
                      let fi = workspace.collections[ci].folders?.firstIndex(where: { $0.id == folderID }) {
                var folders = workspace.collections[ci].folders ?? []
                if address.kind == "folder.name" {
                    folders[fi].name = changed(folders[fi].name)
                } else {
                    mutateKV(&folders[fi].variables, rowID: address.rowID, kind: address.kind, transform: changed)
                }
                workspace.collections[ci].folders = folders
            } else if let requestID = address.requestID,
                      let ri = workspace.collections[ci].requests.firstIndex(where: { $0.id == requestID }) {
                var request = workspace.collections[ci].requests[ri]
                switch address.kind {
                case "request.name": request.name = changed(request.name)
                case "request.url": request.url = changed(request.url)
                case "request.description": request.descriptionText = changed(request.descriptionText ?? "")
                case "request.body": request.body = changed(request.body)
                case "request.binaryPath": request.binaryPath = changed(request.binaryPath ?? "")
                case "request.graphqlVariables": request.graphqlVariables = changed(request.graphqlVariables ?? "")
                case "request.preScript": request.preScript = changed(request.preScript)
                case "request.postScript": request.postScript = changed(request.postScript)
                case let kind where kind.hasPrefix("request.param."):
                    mutateKV(&request.params, rowID: address.rowID, kind: kind, transform: changed)
                case let kind where kind.hasPrefix("request.header."):
                    mutateKV(&request.headers, rowID: address.rowID, kind: kind, transform: changed)
                case let kind where kind.hasPrefix("request.form."):
                    mutateKV(&request.form, rowID: address.rowID, kind: kind, transform: changed)
                case let kind where kind.hasPrefix("request.multipart."):
                    var parts = request.multipart ?? []
                    if let index = parts.firstIndex(where: { $0.id == address.rowID }) {
                        if kind.hasSuffix(".key") { parts[index].key = changed(parts[index].key) }
                        else if kind.hasSuffix(".value") { parts[index].value = changed(parts[index].value) }
                        else { parts[index].filePath = changed(parts[index].filePath) }
                    }
                    request.multipart = parts
                case let kind where kind.hasPrefix("request.auth."):
                    if var auth = request.auth {
                        switch kind {
                        case "request.auth.token": auth.token = changed(auth.token)
                        case "request.auth.username": auth.username = changed(auth.username)
                        case "request.auth.password": auth.password = changed(auth.password)
                        case "request.auth.key": auth.key = changed(auth.key)
                        case "request.auth.value": auth.value = changed(auth.value)
                        default: break
                        }
                        request.auth = auth
                    }
                default: break
                }
                workspace.collections[ci].requests[ri] = request
            }
        } else if let environmentID = address.environmentID,
                  let ei = workspace.environments.firstIndex(where: { $0.id == environmentID }) {
            if address.kind == "environment.name" {
                workspace.environments[ei].name = changed(workspace.environments[ei].name)
            } else {
                mutateKV(&workspace.environments[ei].variables, rowID: address.rowID,
                         kind: address.kind, transform: changed)
            }
        }
        return replaced
    }

    static func replaceAll(_ hits: [SearchHit], in workspace: inout Workspace, query: String,
                           with replacement: String, caseSensitive: Bool) -> Int {
        hits.reduce(0) { count, hit in
            count + replace(hit, in: &workspace, query: query, with: replacement,
                            caseSensitive: caseSensitive, allOccurrences: true)
        }
    }

    private static func mutateKV(_ items: inout [KVItem], rowID: UUID?, kind: String,
                                 transform: (String) -> String) {
        guard let index = items.firstIndex(where: { $0.id == rowID }) else { return }
        if kind.hasSuffix(".key") { items[index].key = transform(items[index].key) }
        else { items[index].value = transform(items[index].value) }
    }

    private static func occurrences(in value: String, query: String, caseSensitive: Bool) -> Int {
        guard !query.isEmpty else { return 0 }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var count = 0
        var cursor = value.startIndex
        while cursor < value.endIndex,
              let match = value.range(of: query, options: options, range: cursor..<value.endIndex) {
            count += 1
            cursor = match.upperBound
        }
        return count
    }
}
