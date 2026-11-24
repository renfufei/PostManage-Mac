import AppKit

@MainActor final class AppLifecycle: NSObject, NSApplicationDelegate {
    weak var store: AppStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store,
              store.requestDrafts.keys.contains(where: { store.requestHasUnsavedChanges($0) }) else {
            return .terminateNow
        }
        let chinese = UserDefaults.standard.string(forKey: "appLanguage") == "zh-Hans"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = chinese ? "退出前保存请求修改？" : "Save request changes before quitting?"
        alert.informativeText = chinese
            ? "未保存的请求草稿只保留在本次运行中。"
            : "Unsaved request drafts are kept only for this app session."
        alert.addButton(withTitle: chinese ? "全部保存并退出" : "Save All and Quit")
        alert.addButton(withTitle: chinese ? "丢弃并退出" : "Discard and Quit")
        alert.addButton(withTitle: chinese ? "取消" : "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if store.saveAllRequestDrafts() { return .terminateNow }
            let errorAlert = NSAlert()
            errorAlert.alertStyle = .critical
            errorAlert.messageText = chinese ? "保存失败" : "Save failed"
            errorAlert.informativeText = store.saveError ??
                L10n.string("Unknown error", language: chinese ? "zh-Hans" : "en")
            errorAlert.runModal()
            return .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
