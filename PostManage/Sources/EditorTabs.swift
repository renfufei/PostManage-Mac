import Foundation

enum EditorTab: Hashable, Identifiable {
    case request(UUID)
    case environment(UUID)

    var id: String {
        switch self {
        case .request(let id): return "request:\(id.uuidString)"
        case .environment(let id): return "environment:\(id.uuidString)"
        }
    }
}

enum EditorTabs {
    static func opening(_ tab: EditorTab, in tabs: [EditorTab]) -> [EditorTab] {
        tabs.contains(tab) ? tabs : tabs + [tab]
    }

    static func closing(_ tab: EditorTab, in tabs: [EditorTab]) -> [EditorTab] {
        tabs.filter { $0 != tab }
    }

    static func available(_ tabs: [EditorTab], in workspace: Workspace) -> [EditorTab] {
        let requests = Set(workspace.collections.flatMap { $0.requests.map(\.id) })
        let environments = Set(workspace.environments.map(\.id))
        return tabs.filter {
            switch $0 {
            case .request(let id): requests.contains(id)
            case .environment(let id): environments.contains(id)
            }
        }
    }
}
