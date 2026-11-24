import Foundation

enum CollectionOrganizer {
    static func move(_ item: String, in collection: inout RequestCollection,
                     to parentID: UUID?, before targetID: UUID? = nil) -> Bool {
        let parts = item.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let itemID = UUID(uuidString: String(parts[1])) else { return false }
        if targetID == itemID { return false }
        if let parentID, !(collection.folders ?? []).contains(where: { $0.id == parentID }) { return false }
        let sourceParent: UUID?
        switch parts[0] {
        case "request":
            guard let index = collection.requests.firstIndex(where: { $0.id == itemID }) else { return false }
            sourceParent = collection.requests[index].folderID
            collection.requests[index].folderID = parentID
        case "folder":
            guard let index = collection.folders?.firstIndex(where: { $0.id == itemID }) else { return false }
            sourceParent = collection.folders?[index].parentID
            guard itemID != parentID, !isDescendant(parentID, of: itemID, in: collection) else { return false }
            collection.folders?[index].parentID = parentID
        default: return false
        }
        normalize(parentID: sourceParent, in: &collection)
        var siblings = entries(parentID: parentID, in: collection).filter { $0 != itemID }
        if let targetID, let index = siblings.firstIndex(of: targetID) {
            siblings.insert(itemID, at: index)
        } else {
            siblings.append(itemID)
        }
        assignOrders(siblings, in: &collection)
        return true
    }

    private static func isDescendant(_ possible: UUID?, of ancestor: UUID,
                                     in collection: RequestCollection) -> Bool {
        var current = possible
        var seen = Set<UUID>()
        while let id = current, !seen.contains(id) {
            if id == ancestor { return true }
            seen.insert(id)
            current = collection.folders?.first(where: { $0.id == id })?.parentID
        }
        return false
    }

    private static func entries(parentID: UUID?, in collection: RequestCollection) -> [UUID] {
        let folders = (collection.folders ?? []).filter { $0.parentID == parentID }
            .map { ($0.id, $0.sortOrder) }
        let requests = collection.requests.filter { $0.folderID == parentID }
            .map { ($0.id, $0.sortOrder ?? 0) }
        return (folders + requests).sorted { $0.1 < $1.1 }.map(\.0)
    }

    private static func normalize(parentID: UUID?, in collection: inout RequestCollection) {
        assignOrders(entries(parentID: parentID, in: collection), in: &collection)
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
