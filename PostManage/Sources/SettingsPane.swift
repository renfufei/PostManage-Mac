import AppKit
import SwiftUI

struct SettingsPane: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("showQueryParamsInURL") private var showQueryParamsInURL = true
    @AppStorage("sidebarWidth") private var sidebarWidth = 250.0
    @AppStorage("collectionsPaneFraction") private var collectionsPaneFraction = 0.62
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false
    @AppStorage("environmentsCollapsed") private var environmentsCollapsed = false
    @AppStorage("requestEditorPaneFraction") private var requestEditorPaneFraction = 0.56

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L10n.string("Settings", language: appLanguage)).font(.title2.monospaced().bold())
                Spacer()
                Button(L10n.string("Done", language: appLanguage)) { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            Divider()
            HStack {
                Text(L10n.string("Language", language: appLanguage))
                Spacer()
                Picker(L10n.string("Language", language: appLanguage), selection: $appLanguage) {
                    Text("English").tag("en")
                    Text("简体中文").tag("zh-Hans")
                }.labelsHidden().frame(width: 170)
            }
            Toggle(L10n.string("Show Params in URL", language: appLanguage), isOn: $showQueryParamsInURL)
            Divider()
            HStack {
                Button(L10n.string("Open Data Folder", language: appLanguage)) {
                    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("PostManage", isDirectory: true)
                    NSWorkspace.shared.open(folder)
                }
                .help(L10n.string("Open local workspace and history files in Finder", language: appLanguage))
                Button(L10n.string("Reset Layout", language: appLanguage)) {
                    sidebarWidth = 250
                    collectionsPaneFraction = 0.62
                    requestEditorPaneFraction = 0.56
                    sidebarCollapsed = false
                    environmentsCollapsed = false
                }
                .help(L10n.string("Restore default sidebar sizes and visibility", language: appLanguage))
                Spacer()
            }
            Text(L10n.string("Data stays on this Mac. Collection and environment edits save automatically; request edits need Save.", language: appLanguage))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
            Divider()
            HStack {
                Spacer()
                Text(L10n.format("Version %@", language: appLanguage,
                                 Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .font(.system(.body, design: .monospaced))
        .environment(\.locale, Locale(identifier: appLanguage))
    }
}
