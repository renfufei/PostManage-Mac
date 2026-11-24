import Foundation

enum RequestDrafts {
    static func hasUnsavedChanges(_ id: UUID, drafts: [UUID: RequestItem],
                                  saved: RequestItem?, saveFailed: Bool = false) -> Bool {
        guard let draft = drafts[id] else { return false }
        return draft != saved || saveFailed
    }

    static func overlay(_ drafts: [UUID: RequestItem], on workspace: Workspace) -> Workspace {
        var result = workspace
        for collectionIndex in result.collections.indices {
            for requestIndex in result.collections[collectionIndex].requests.indices {
                let id = result.collections[collectionIndex].requests[requestIndex].id
                if let draft = drafts[id] {
                    result.collections[collectionIndex].requests[requestIndex] = draft
                }
            }
        }
        return result
    }

    @discardableResult static func preserveUnsavedRequests(_ drafts: [UUID: RequestItem],
                                                            previous: Workspace,
                                                            merged: inout Workspace) -> Int {
        var original: [UUID: RequestItem] = [:]
        for collection in previous.collections {
            for request in collection.requests { original[request.id] = request }
        }
        var skipped = 0
        for collectionIndex in merged.collections.indices {
            for requestIndex in merged.collections[collectionIndex].requests.indices {
                let imported = merged.collections[collectionIndex].requests[requestIndex]
                guard let saved = original[imported.id],
                      hasUnsavedChanges(imported.id, drafts: drafts, saved: saved),
                      imported != saved else { continue }
                merged.collections[collectionIndex].requests[requestIndex] = saved
                skipped += 1
            }
        }
        return skipped
    }
}
