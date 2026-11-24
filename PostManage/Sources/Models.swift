import Foundation

struct KVItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var key = ""
    var value = ""
}

struct AuthConfig: Codable, Equatable {
    var type = "none"
    var token = ""
    var username = ""
    var password = ""
    var key = ""
    var value = ""
    var placement = "header"
}

struct MultipartPart: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var key = ""
    var kind = "text"
    var value = ""
    var filePath = ""
}

struct RequestItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var importKey: String?
    var folderID: UUID?
    var sortOrder: Int?
    var name = "New Request"
    var method = "GET"
    var url = ""
    var params: [KVItem] = [KVItem()]
    var headers: [KVItem] = [KVItem()]
    var bodyType = "none"
    var body = ""
    var rawContentType: String?
    var binaryPath: String?
    var graphqlVariables: String?
    var form: [KVItem] = [KVItem()]
    var multipart: [MultipartPart]?
    var auth: AuthConfig?
    var descriptionText: String?
    var preScript = ""
    var postScript = ""
}

struct CollectionFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var importKey: String?
    var name = "New Folder"
    var parentID: UUID?
    var sortOrder = 0
    var variables: [KVItem] = []
}

struct RequestCollection: Codable, Identifiable, Equatable {
    var id = UUID()
    var importKey: String?
    var name = "New Collection"
    var requests: [RequestItem] = []
    var variables: [KVItem]?
    var folders: [CollectionFolder]?

    func folderPath(for request: RequestItem) -> String {
        folderPath(for: request.folderID)
    }

    func folderPath(for folderID: UUID?) -> String {
        guard var id = folderID else { return "" }
        var names: [String] = []
        var seen = Set<UUID>()
        while let folder = (folders ?? []).first(where: { $0.id == id }), !seen.contains(id) {
            names.insert(folder.name, at: 0)
            seen.insert(id)
            guard let parent = folder.parentID else { break }
            id = parent
        }
        return names.joined(separator: " / ")
    }

    func scopedVariables(for request: RequestItem) -> [KVItem] {
        guard var id = request.folderID else { return [] }
        var chain: [CollectionFolder] = []
        var seen = Set<UUID>()
        while let folder = (folders ?? []).first(where: { $0.id == id }), !seen.contains(id) {
            chain.insert(folder, at: 0)
            seen.insert(id)
            guard let parent = folder.parentID else { break }
            id = parent
        }
        return chain.flatMap(\.variables)
    }
}

struct Environment: Codable, Identifiable, Equatable {
    var id = UUID()
    var importKey: String?
    var name = "New Environment"
    var variables: [KVItem] = [KVItem()]
}

struct Workspace: Codable {
    var collections: [RequestCollection] = []
    var environments: [Environment] = []
    var selectedEnvironmentID: UUID?
}

struct ResponseData {
    var status: Int
    var statusText: String
    var duration: TimeInterval
    var size: Int
    var headers: [(String, String)]
    var body: String
    var rawData: Data? = nil
    var mimeType: String? = nil
    var finalURL: String? = nil
    var cookies: [ResponseCookie] = []
    var redirects: [ResponseRedirect] = []
    var timings: ResponseTimings? = nil
}

struct ResponseCookie: Identifiable {
    var id: String { name + "@" + domain + path }
    var name: String
    var value: String
    var domain: String
    var path: String
}

struct ResponseRedirect: Identifiable {
    var id = UUID()
    var status: Int
    var from: String
    var to: String
}

struct ResponseTimings {
    var dns: TimeInterval?
    var connect: TimeInterval?
    var tls: TimeInterval?
    var upload: TimeInterval?
    var wait: TimeInterval?
    var download: TimeInterval?
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let level: String
    let message: String
}

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var requestID: UUID
    var collectionName: String
    var requestName: String
    var method: String
    var url: String
    var status: Int?
    var duration: TimeInterval?
    var error: String?
    var passedTests = 0
    var failedTests = 0
}

struct RunResult: Identifiable {
    var id: UUID { requestID }
    var requestID: UUID
    var requestName: String
    var status: Int?
    var duration: TimeInterval?
    var passedTests: Int
    var failedTests: Int
    var error: String?
}
