import Foundation

enum WorkspaceMigration {
    static func migrateLegacyFolderCollections(_ workspace: inout Workspace) -> Bool {
        let legacy = workspace.collections.filter {
            $0.folders == nil && ($0.importKey?.contains("/folder:") == true)
        }
        guard !legacy.isEmpty else { return false }
        var collections = workspace.collections.filter {
            !($0.folders == nil && ($0.importKey?.contains("/folder:") == true))
        }
        for old in legacy {
            guard let key = old.importKey,
                  let range = key.range(of: "/folder:") else { continue }
            let rootKey = String(key[..<range.lowerBound])
            let names = old.name.components(separatedBy: " / ")
            let rootName = names.first ?? old.name
            let rootIndex: Int
            if let index = collections.firstIndex(where: { $0.importKey == rootKey }) {
                rootIndex = index
            } else {
                collections.append(RequestCollection(id: old.id, importKey: rootKey, name: rootName,
                                                     requests: [], variables: old.variables, folders: []))
                rootIndex = collections.count - 1
            }
            let folderKeys = key.components(separatedBy: "/folder:").dropFirst()
            var parentID: UUID?
            var currentKey = rootKey
            for (offset, segment) in folderKeys.enumerated() {
                currentKey += "/folder:" + segment
                let name = names.indices.contains(offset + 1) ? names[offset + 1] : "Folder"
                var folders = collections[rootIndex].folders ?? []
                if let existing = folders.first(where: { $0.importKey == currentKey }) {
                    parentID = existing.id
                } else {
                    let folder = CollectionFolder(importKey: currentKey, name: name,
                                                  parentID: parentID, sortOrder: offset,
                                                  variables: offset == folderKeys.count - 1 ? (old.variables ?? []) : [])
                    folders.append(folder)
                    collections[rootIndex].folders = folders
                    parentID = folder.id
                }
            }
            for var request in old.requests {
                request.folderID = parentID
                if request.sortOrder == nil { request.sortOrder = collections[rootIndex].requests.count }
                collections[rootIndex].requests.append(request)
            }
        }
        workspace.collections = collections
        return true
    }
}
