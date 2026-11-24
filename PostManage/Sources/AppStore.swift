import Foundation
import SwiftUI

@MainActor final class AppStore: ObservableObject {
    @Published var workspace: Workspace {
        didSet { save() }
    }
    @Published var response: ResponseData?
    @Published var lastError: String?
    @Published var responses: [UUID: ResponseData] = [:]
    @Published var errors: [UUID: String] = [:]
    @Published var requestDrafts: [UUID: RequestItem] = [:]
    @Published var logs: [LogEntry] = []
    @Published var sending = false
    @Published private(set) var sendingRequestID: UUID?
    @Published private(set) var cancellingRequest = false
    @Published var history: [HistoryEntry] = [] {
        didSet { saveHistory() }
    }
    @Published var runningCollectionID: UUID?
    @Published private(set) var cancellingCollection = false
    @Published var runResults: [RunResult] = []
    @Published private(set) var saveError: String?
    @Published private(set) var historySaveError: String?
    @Published private(set) var workspaceLoadError: String?

    private let fileURL: URL
    private let historyURL: URL
    private var workspaceSaveBlocked = false
    private var sendTask: Task<Void, Never>?
    private var collectionTask: Task<Void, Never>?

    init(directory overrideDirectory: URL? = nil) {
        let directory = overrideDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PostManage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("workspace.json")
        historyURL = directory.appendingPathComponent("history.json")
        var sourceData: Data?
        var decodedWorkspace: Workspace?
        var readFailure: Error?
        var migrationBackupFailure: Error?
        var migrationWriteFailure: Error?
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                sourceData = data
                decodedWorkspace = try JSONDecoder().decode(Workspace.self, from: data)
            } catch {
                readFailure = error
            }
        }
        if let data = sourceData, var decoded = decodedWorkspace {
            if WorkspaceMigration.migrateLegacyFolderCollections(&decoded) {
                let backup = directory.appendingPathComponent("workspace.pre-folder-migration.json")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    do { try data.write(to: backup, options: .atomic) }
                    catch { migrationBackupFailure = error }
                }
                if migrationBackupFailure == nil {
                    do {
                        let migrated = try JSONEncoder().encode(decoded)
                        try migrated.write(to: fileURL, options: .atomic)
                    } catch { migrationWriteFailure = error }
                }
            }
            workspace = decoded
        } else {
            var starter = RequestItem()
            starter.name = L10n.string("Example Request", language: L10n.selectedLanguage)
            starter.url = "http://localhost:8080"
            workspace = Workspace(collections: [RequestCollection(
                name: L10n.string("My Collection", language: L10n.selectedLanguage), requests: [starter])],
                                  environments: [Environment(name: L10n.string("Local", language: L10n.selectedLanguage))])
        }
        if let readFailure {
            workspaceLoadError = readFailure.localizedDescription
            workspaceSaveBlocked = true
            saveError = L10n.string("The existing workspace could not be read. Recover it before saving changes.",
                                    language: L10n.selectedLanguage)
        } else if let migrationBackupFailure {
            workspaceLoadError = L10n.format("Could not back up the workspace before migration: %@",
                                             language: L10n.selectedLanguage,
                                             migrationBackupFailure.localizedDescription)
            workspaceSaveBlocked = true
            saveError = L10n.string("The workspace needs recovery before saving changes.",
                                    language: L10n.selectedLanguage)
        } else if let migrationWriteFailure {
            saveError = migrationWriteFailure.localizedDescription
        }
        if let data = try? Data(contentsOf: historyURL),
           let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = saved
        }
        log(L10n.string("Workspace loaded from local storage", language: L10n.selectedLanguage))
        if let readFailure {
            log(L10n.format("Workspace load failed: %@", language: L10n.selectedLanguage,
                            readFailure.localizedDescription), level: "ERROR")
        }
        if let migrationBackupFailure {
            log(L10n.format("Workspace migration backup failed: %@", language: L10n.selectedLanguage,
                            migrationBackupFailure.localizedDescription), level: "ERROR")
        }
        if let migrationWriteFailure {
            log(L10n.format("Workspace migration save failed: %@", language: L10n.selectedLanguage,
                            migrationWriteFailure.localizedDescription), level: "ERROR")
        }
    }

    private func save() {
        guard !workspaceSaveBlocked else {
            saveError = L10n.string("The workspace needs recovery before saving changes.",
                                    language: L10n.selectedLanguage)
            return
        }
        do {
            let data = try JSONEncoder().encode(workspace)
            try data.write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            log(L10n.format("Save failed: %@", language: L10n.selectedLanguage,
                            error.localizedDescription), level: "ERROR")
        }
    }

    func retrySave() {
        save()
        saveHistory()
    }

    @discardableResult func recoverUnreadableWorkspace() throws -> URL? {
        guard workspaceSaveBlocked else { return nil }
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "yyyyMMdd-HHmmss"
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("workspace.backup-\(date.string(from: Date()))-\(UUID().uuidString.prefix(8)).json")
        try FileManager.default.copyItem(at: fileURL, to: backup)
        workspaceSaveBlocked = false
        workspaceLoadError = nil
        save()
        if let saveError {
            throw NSError(domain: "PostManage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(saveError) Backup: \(backup.path)"])
        }
        log(L10n.format("Workspace backed up to %@; current workspace saved",
                        language: L10n.selectedLanguage, backup.lastPathComponent), level: "WARN")
        return backup
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL, options: .atomic)
            historySaveError = nil
        } catch {
            historySaveError = error.localizedDescription
            log(L10n.format("History save failed: %@", language: L10n.selectedLanguage,
                            error.localizedDescription), level: "ERROR")
        }
    }

    func log(_ message: String, level: String = "INFO") {
        logs.append(LogEntry(level: level, message: message))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    func addCollection() -> UUID {
        var collection = RequestCollection()
        collection.name = L10n.string("New Collection", language: L10n.selectedLanguage)
        workspace.collections.append(collection)
        return collection.id
    }

    func addRequest(to collectionID: UUID, folderID: UUID? = nil) -> UUID? {
        guard let index = workspace.collections.firstIndex(where: { $0.id == collectionID }) else { return nil }
        var request = RequestItem()
        request.name = L10n.string("New Request", language: L10n.selectedLanguage)
        request.folderID = folderID
        request.sortOrder = ((workspace.collections[index].requests.filter { $0.folderID == folderID }.compactMap(\.sortOrder).max() ?? -1) + 1)
        workspace.collections[index].requests.append(request)
        return request.id
    }

    func addFolder(to collectionID: UUID, parentID: UUID? = nil) -> UUID? {
        guard let index = workspace.collections.firstIndex(where: { $0.id == collectionID }) else { return nil }
        var folder = CollectionFolder()
        folder.name = L10n.string("New Folder", language: L10n.selectedLanguage)
        folder.parentID = parentID
        folder.sortOrder = ((workspace.collections[index].folders ?? []).filter { $0.parentID == parentID }.map(\.sortOrder).max() ?? -1) + 1
        if workspace.collections[index].folders == nil { workspace.collections[index].folders = [] }
        workspace.collections[index].folders?.append(folder)
        return folder.id
    }

    func deleteFolder(_ folderID: UUID, from collectionID: UUID) {
        guard let index = workspace.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        var ids = Set([folderID])
        var changed = true
        while changed {
            let previous = ids.count
            for folder in workspace.collections[index].folders ?? [] where folder.parentID.map(ids.contains) == true {
                ids.insert(folder.id)
            }
            changed = ids.count != previous
        }
        workspace.collections[index].folders?.removeAll { ids.contains($0.id) }
        workspace.collections[index].requests.removeAll { $0.folderID.map(ids.contains) == true }
    }

    func deleteRequest(_ id: UUID) {
        for index in workspace.collections.indices {
            workspace.collections[index].requests.removeAll { $0.id == id }
        }
    }

    func addEnvironment() -> UUID {
        var environment = Environment()
        environment.name = L10n.string("New Environment", language: L10n.selectedLanguage)
        workspace.environments.append(environment)
        return environment.id
    }

    func request(_ id: UUID) -> RequestItem? {
        workspace.collections.flatMap(\.requests).first { $0.id == id }
    }

    func collection(_ id: UUID) -> RequestCollection? {
        workspace.collections.first { $0.id == id }
    }

    func updateCollection(_ value: RequestCollection) {
        if let index = workspace.collections.firstIndex(where: { $0.id == value.id }) {
            workspace.collections[index] = value
        }
    }

    func updateRequest(_ value: RequestItem) {
        for c in workspace.collections.indices {
            if let r = workspace.collections[c].requests.firstIndex(where: { $0.id == value.id }) {
                workspace.collections[c].requests[r] = value
                return
            }
        }
    }

    func requestHasUnsavedChanges(_ id: UUID) -> Bool {
        RequestDrafts.hasUnsavedChanges(id, drafts: requestDrafts,
                                        saved: request(id), saveFailed: saveError != nil)
    }

    @discardableResult func saveRequestDraft(_ id: UUID) -> Bool {
        guard let draft = requestDrafts[id], let saved = request(id) else { return false }
        if draft != saved { updateRequest(draft) }
        else if saveError != nil { retrySave() }
        guard saveError == nil else { return false }
        requestDrafts.removeValue(forKey: id)
        return true
    }

    @discardableResult func saveAllRequestDrafts() -> Bool {
        var updated = workspace
        var changed = false
        for collectionIndex in updated.collections.indices {
            for requestIndex in updated.collections[collectionIndex].requests.indices {
                let id = updated.collections[collectionIndex].requests[requestIndex].id
                if let draft = requestDrafts[id], draft != updated.collections[collectionIndex].requests[requestIndex] {
                    updated.collections[collectionIndex].requests[requestIndex] = draft
                    changed = true
                }
            }
        }
        if changed { workspace = updated }
        else if saveError != nil { retrySave() }
        guard saveError == nil else { return false }
        requestDrafts.removeAll()
        return true
    }

    func environment(_ id: UUID) -> Environment? {
        workspace.environments.first { $0.id == id }
    }

    func updateEnvironment(_ value: Environment) {
        if let index = workspace.environments.firstIndex(where: { $0.id == value.id }) {
            workspace.environments[index] = value
        }
    }

    private func persistVariables(_ variables: [String: String], baseline: [String: String], environmentID: UUID?) {
        guard let environmentID, var target = environment(environmentID) else { return }
        for (key, value) in variables where baseline[key] != value {
            if let index = target.variables.firstIndex(where: { $0.key == key }) {
                target.variables[index].value = value
            } else {
                target.variables.append(KVItem(key: key, value: value))
            }
        }
        updateEnvironment(target)
    }

    func send(_ item: RequestItem) {
        guard !sending && runningCollectionID == nil else { return }
        sending = true
        sendingRequestID = item.id
        cancellingRequest = false
        sendTask = Task {
            _ = await execute(item)
            sending = false
            sendingRequestID = nil
            cancellingRequest = false
            sendTask = nil
        }
    }

    func cancelSend() {
        guard sending else { return }
        cancellingRequest = true
        sendTask?.cancel()
    }

    func runCollection(_ collectionID: UUID) {
        guard runningCollectionID == nil, !sending,
              let collection = self.collection(collectionID) else { return }
        runningCollectionID = collectionID
        cancellingCollection = false
        runResults = []
        collectionTask = Task {
            for item in collection.requests {
                guard !Task.isCancelled else { break }
                let result = await execute(item)
                runResults.append(result)
            }
            runningCollectionID = nil
            cancellingCollection = false
            collectionTask = nil
        }
    }

    func cancelCollection() {
        guard runningCollectionID != nil else { return }
        cancellingCollection = true
        collectionTask?.cancel()
    }

    func clearHistory() {
        history.removeAll()
    }

    private func execute(_ item: RequestItem) async -> RunResult {
        response = nil
        lastError = nil
        responses[item.id] = nil
        errors[item.id] = nil
        log(L10n.format("Sending %@ %@", language: L10n.selectedLanguage,
                        item.method, HistorySanitizer.url(item.url)))
        let collection = workspace.collections.first { $0.requests.contains(where: { $0.id == item.id }) }
        let environmentID = workspace.selectedEnvironmentID
        let environment = workspace.environments.first { $0.id == environmentID }
        var variables: [String: String] = [:]
        for variable in collection?.variables ?? [] where variable.enabled && !variable.key.isEmpty {
            variables[variable.key] = variable.value
        }
        if let collection {
            for variable in collection.scopedVariables(for: item) where variable.enabled && !variable.key.isEmpty {
                variables[variable.key] = variable.value
            }
        }
        for variable in environment?.variables ?? [] where variable.enabled && !variable.key.isEmpty {
            variables[variable.key] = variable.value
        }
        var received: ResponseData?
        var failure: String?
        var passedTests = 0
        var failedTests = 0
        do {
            try Task.checkCancellation()
            let beforePre = variables
            let pre = try await IsolatedScriptRunner.run(item.preScript, variables: variables, request: item)
            try Task.checkCancellation()
            variables = pre.variables
            pre.logs.forEach { log($0, level: "SCRIPT") }
            persistVariables(variables, baseline: beforePre, environmentID: environmentID)
            let result = try await RequestEngine.send(item, variables: variables)
            try Task.checkCancellation()
            received = result
            response = result
            responses[item.id] = result
            log(L10n.format("Received %d in %d ms · %d bytes", language: L10n.selectedLanguage,
                            result.status, Int(result.duration * 1000), result.size))
            let beforePost = variables
            let post = try await IsolatedScriptRunner.run(item.postScript, variables: variables, response: result, request: item)
            try Task.checkCancellation()
            variables = post.variables
            for line in post.logs {
                if line.hasPrefix("PASS ") { passedTests += 1 }
                if line.hasPrefix("FAIL ") { failedTests += 1 }
                log(line, level: "SCRIPT")
            }
            persistVariables(variables, baseline: beforePost, environmentID: environmentID)
        } catch {
            failure = Task.isCancelled
                ? L10n.string("Cancelled", language: L10n.selectedLanguage)
                : error.localizedDescription
            lastError = failure
            errors[item.id] = failure
            log(failure ?? L10n.string("Unknown error", language: L10n.selectedLanguage),
                level: Task.isCancelled ? "WARN" : "ERROR")
        }
        let entry = HistoryEntry(requestID: item.id,
                                 collectionName: collection?.name ?? L10n.string("Collection", language: L10n.selectedLanguage),
                                 requestName: item.name, method: item.method, url: HistorySanitizer.url(item.url),
                                 status: received?.status, duration: received?.duration, error: failure,
                                 passedTests: passedTests, failedTests: failedTests)
        history.insert(entry, at: 0)
        if history.count > 500 { history.removeLast(history.count - 500) }
        return RunResult(requestID: item.id, requestName: item.name, status: received?.status,
                         duration: received?.duration, passedTests: passedTests,
                         failedTests: failedTests, error: failure)
    }

}
