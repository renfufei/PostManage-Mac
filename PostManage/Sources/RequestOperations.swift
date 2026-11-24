import Foundation

struct RequestClipboardPayload {
    enum Operation { case copy, cut }
    let operation: Operation
    let sourceID: UUID
    let snapshot: RequestItem
}

enum RequestOperations {
    static func duplicate(_ requestID: UUID, in collection: inout RequestCollection) -> UUID? {
        guard let source = collection.requests.first(where: { $0.id == requestID }) else { return nil }
        let siblings = orderedEntries(in: collection, parentID: source.folderID)
        guard let sourceIndex = siblings.firstIndex(of: requestID) else { return nil }
        var copy = freshCopy(source)
        copy.name += " Copy"
        collection.requests.append(copy)
        var ordered = siblings
        ordered.insert(copy.id, at: sourceIndex + 1)
        assignOrders(ordered, in: &collection)
        return copy.id
    }

    static func paste(_ payload: RequestClipboardPayload, into collectionID: UUID,
                      folderID: UUID? = nil, workspace: inout Workspace) -> UUID? {
        guard let destination = workspace.collections.firstIndex(where: { $0.id == collectionID }) else { return nil }
        if let folderID, (workspace.collections[destination].folders ?? []).contains(where: { $0.id == folderID }) == false {
            return nil
        }
        var request: RequestItem
        switch payload.operation {
        case .copy:
            request = freshCopy(payload.snapshot)
        case .cut:
            guard let sourceCollection = workspace.collections.firstIndex(where: {
                $0.requests.contains(where: { $0.id == payload.sourceID })
            }), let sourceRequest = workspace.collections[sourceCollection].requests.first(where: { $0.id == payload.sourceID }) else {
                return nil
            }
            request = sourceRequest
            workspace.collections[sourceCollection].requests.removeAll { $0.id == payload.sourceID }
        }
        request.folderID = folderID
        let collection = workspace.collections[destination]
        let folderOrders = (collection.folders ?? []).filter { $0.parentID == folderID }.map(\.sortOrder)
        let requestOrders = collection.requests.filter { $0.folderID == folderID }.compactMap(\.sortOrder)
        request.sortOrder = (folderOrders + requestOrders).max().map { $0 + 1 } ?? 0
        workspace.collections[destination].requests.append(request)
        return request.id
    }

    private static func freshCopy(_ source: RequestItem) -> RequestItem {
        var result = source
        result.id = UUID()
        result.importKey = nil
        result.params = source.params.map { var item = $0; item.id = UUID(); return item }
        result.headers = source.headers.map { var item = $0; item.id = UUID(); return item }
        result.form = source.form.map { var item = $0; item.id = UUID(); return item }
        result.multipart = source.multipart?.map { var item = $0; item.id = UUID(); return item }
        return result
    }

    private static func orderedEntries(in collection: RequestCollection, parentID: UUID?) -> [UUID] {
        let folders = (collection.folders ?? []).filter { $0.parentID == parentID }.map { ($0.id, $0.sortOrder) }
        let requests = collection.requests.filter { $0.folderID == parentID }.map { ($0.id, $0.sortOrder ?? 0) }
        return (folders + requests).sorted { $0.1 < $1.1 }.map(\.0)
    }

    private static func assignOrders(_ ids: [UUID], in collection: inout RequestCollection) {
        for (order, id) in ids.enumerated() {
            if let index = collection.requests.firstIndex(where: { $0.id == id }) {
                collection.requests[index].sortOrder = order
            } else if let index = collection.folders?.firstIndex(where: { $0.id == id }) {
                collection.folders?[index].sortOrder = order
            }
        }
    }
}
