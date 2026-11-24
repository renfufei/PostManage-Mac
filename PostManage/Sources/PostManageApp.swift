import SwiftUI
import UniformTypeIdentifiers
import AppKit

private enum CollectionTreeEntry: Identifiable {
    case folder(CollectionFolder)
    case request(RequestItem)

    var id: UUID {
        switch self {
        case .folder(let folder): folder.id
        case .request(let request): request.id
        }
    }

    var order: Int {
        switch self {
        case .folder(let folder): folder.sortOrder
        case .request(let request): request.sortOrder ?? 0
        }
    }
}

@main struct PostManageApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @StateObject private var store = AppStore()
    @AppStorage("appLanguage") private var appLanguage = "en"
    init() {
        if CommandLine.arguments.contains("--script-worker") {
            ScriptWorker.runAndExit()
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: appLanguage))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 1100, minHeight: 700)
                .background(WindowFrameMemory())
                .onAppear { lifecycle.store = store }
        }
        .defaultSize(width: 1360, height: 850)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(appLanguage == "zh-Hans" ? "搜索" : "Search") {
                Button(appLanguage == "zh-Hans" ? "在集合中查找" : "Find in Collection") {
                    NotificationCenter.default.post(name: .postManageSearch, object: nil, userInfo: ["mode": "current"])
                }.keyboardShortcut("f", modifiers: .command)
                Button(appLanguage == "zh-Hans" ? "在工作区中查找" : "Find in Workspace") {
                    NotificationCenter.default.post(name: .postManageSearch, object: nil, userInfo: ["mode": "global"])
                }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button(appLanguage == "zh-Hans" ? "查找并替换" : "Find and Replace") {
                    NotificationCenter.default.post(name: .postManageSearch, object: nil, userInfo: ["mode": "replace"])
                }.keyboardShortcut("f", modifiers: [.command, .option])
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("sidebarWidth") private var sidebarWidth = 250.0
    @AppStorage("collectionsPaneFraction") private var collectionsPaneFraction = 0.62
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false
    @AppStorage("showQueryParamsInURL") private var showQueryParamsInURL = true
    @AppStorage("environmentsCollapsed") private var environmentsCollapsed = false
    @AppStorage("requestEditorPaneFraction") private var requestEditorPaneFraction = 0.56
    @State private var dragStartWidth: Double?
    @State private var dragStartCollectionsHeight: Double?
    @State private var dragStartEditorHeight: Double?
    @State private var selectedRequestID: UUID?
    @State private var selectedEnvironmentID: UUID?
    @State private var selectedCollectionID: UUID?
    @State private var expandedCollectionIDs: Set<UUID> = []
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var selectedFolderID: UUID?
    @State private var selectedTab = "Params"
    @State private var selectedScriptTab = "Pre-request"
    @State private var showingImporter = false
    @State private var importError = ""
    @State private var importNoticeTitle = "Import failed"
    @State private var showingImportError = false
    @State private var showingRenameCollection = false
    @State private var renamingCollectionID: UUID?
    @State private var collectionNameDraft = ""
    @State private var showingDeleteCollection = false
    @State private var deletingCollectionID: UUID?
    @State private var showingRenameFolder = false
    @State private var renamingFolderID: UUID?
    @State private var folderNameDraft = ""
    @State private var showingDeleteFolder = false
    @State private var deletingFolderID: UUID?
    @State private var deletingFolderCollectionID: UUID?
    @State private var searchOpen = false
    @State private var searchQuery = ""
    @State private var replacement = ""
    @State private var searchScopeID: UUID?
    @State private var searchCaseSensitive = false
    @State private var searchReplaceVisible = false
    @State private var searchContextCollectionID: UUID?
    @State private var openTabs: [EditorTab] = []
    @State private var closingRequestID: UUID?
    @State private var showingUnsavedCloseAlert = false
    @State private var showHistory = false
    @State private var runnerCollection: RequestCollection?
    @State private var jsonFormatError = ""
    @State private var showingJSONFormatError = false
    @State private var showingSettings = false
    @State private var requestClipboard: RequestClipboardPayload?
    @State private var activeDropTargetID: UUID?
    @State private var draggingTreeItem: String?
    @State private var renamingRequestID: UUID?
    @State private var requestNameDraft = ""
    @State private var showingRenameRequest = false
    @State private var deletingRequestID: UUID?
    @State private var showingDeleteRequest = false
    @State private var deletingEnvironmentID: UUID?
    @State private var showingDeleteEnvironment = false
    @State private var showingWorkspaceRecovery = false

    private var requestBinding: Binding<RequestItem>? {
        guard let id = selectedRequestID, let value = store.request(id) else { return nil }
        return Binding(get: { store.requestDrafts[id] ?? store.request(id) ?? value },
                       set: { store.requestDrafts[id] = $0 })
    }

    private var workspaceWithDrafts: Workspace {
        RequestDrafts.overlay(store.requestDrafts, on: store.workspace)
    }

    private func requestHasUnsavedChanges(_ id: UUID) -> Bool {
        store.requestHasUnsavedChanges(id)
    }

    private var unsavedRequestCount: Int {
        store.requestDrafts.keys.filter { store.requestHasUnsavedChanges($0) }.count
    }

    @discardableResult private func saveRequest(_ id: UUID) -> Bool {
        store.saveRequestDraft(id)
    }

    private var environmentBinding: Binding<Environment>? {
        guard let id = selectedEnvironmentID, let value = store.environment(id) else { return nil }
        return Binding(get: { store.environment(id) ?? value }, set: { store.updateEnvironment($0) })
    }

    var body: some View {
        GeometryReader { geometry in
            let maxSidebarWidth = min(520.0, max(210.0, Double(geometry.size.width) - 650.0))
            let visibleSidebarWidth = min(max(sidebarWidth, 210.0), maxSidebarWidth)
            HStack(spacing: 0) {
                if sidebarCollapsed {
                    VStack {
                        Button { sidebarCollapsed = false } label: {
                            Image(systemName: "sidebar.left").frame(width: 24, height: 24)
                        }
                            .buttonStyle(.plain).help(L10n.string("Expand sidebar", language: appLanguage))
                            .padding(.top, 20)
                        Button { openSearch(mode: "global") } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.plain).help(L10n.string("Search workspace (⇧⌘F)", language: appLanguage))
                            .padding(.top, 14)
                        Button { showHistory = true; searchOpen = false } label: { Image(systemName: "clock.arrow.circlepath") }
                            .buttonStyle(.plain).help(L10n.string("Request history", language: appLanguage))
                            .padding(.top, 14)
                        Spacer()
                    }
                    .frame(width: 28)
                    .background(Color(nsColor: .controlBackgroundColor))
                    Divider()
                } else {
                    sidebar
                        .frame(width: visibleSidebarWidth)
                        .background(Color(nsColor: .controlBackgroundColor))
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                        .frame(width: 9)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStartWidth == nil { dragStartWidth = visibleSidebarWidth }
                                sidebarWidth = min(max((dragStartWidth ?? visibleSidebarWidth) + Double(value.translation.width), 210.0), maxSidebarWidth)
                            }
                            .onEnded { _ in dragStartWidth = nil })
                        .onHover { hovering in
                            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                        }
                        .help(L10n.string("Drag to resize sidebar", language: appLanguage))
                }
                VStack(spacing: 0) {
                    if !openTabs.isEmpty { editorTabs }
                    if showHistory {
                        HistoryPane(entries: store.history,
                                    availableRequestIDs: Set(store.workspace.collections.flatMap { $0.requests.map(\.id) }),
                                    onOpen: { entry in
                            if store.request(entry.requestID) != nil {
                                selectedRequestID = entry.requestID
                                selectedEnvironmentID = nil
                                selectedCollectionID = nil
                                selectedFolderID = nil
                                showHistory = false
                            }
                        }, onClear: { store.clearHistory() })
                    } else if searchOpen {
                        SearchPane(workspace: workspaceWithDrafts, query: $searchQuery, replacement: $replacement,
                                   collectionID: $searchScopeID, caseSensitive: $searchCaseSensitive,
                                   showReplace: $searchReplaceVisible,
                                   onNavigate: navigateToSearchHit,
                                   onReplace: replaceSearchHit,
                                   onReplaceAll: replaceAllSearchHits,
                                   onClose: { searchOpen = false })
                    } else if let requestBinding {
                        requestEditor(requestBinding)
                    } else if let selectedFolderID,
                              let collection = store.workspace.collections.first(where: { ($0.folders ?? []).contains(where: { $0.id == selectedFolderID }) }) {
                        folderEditor(collection, folderID: selectedFolderID)
                    } else if let selectedCollectionID,
                              let collection = store.workspace.collections.first(where: { $0.id == selectedCollectionID }) {
                        collectionEditor(collection)
                    } else if let environmentBinding {
                        environmentEditor(environmentBinding)
                    } else {
                        ContentUnavailableView("Select a request", systemImage: "paperplane", description: Text("Choose a request or environment from the sidebar."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedRequestID == nil && selectedEnvironmentID == nil {
                selectedRequestID = store.workspace.collections.first?.requests.first?.id
                if selectedRequestID == nil {
                    selectedEnvironmentID = store.workspace.environments.first?.id
                }
            }
            if let selectedRequestID {
                openTabs = EditorTabs.opening(.request(selectedRequestID), in: openTabs)
            }
            if let selectedEnvironmentID {
                openTabs = EditorTabs.opening(.environment(selectedEnvironmentID), in: openTabs)
            }
            revealActiveRequest(selectedRequestID)
        }
        .onChange(of: selectedRequestID) { _, value in
            if let value {
                openTabs = EditorTabs.opening(.request(value), in: openTabs)
                revealActiveRequest(value)
            }
        }
        .onChange(of: selectedEnvironmentID) { _, value in
            if let value {
                openTabs = EditorTabs.opening(.environment(value), in: openTabs)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .postManageSearch)) { notification in
            let mode = notification.userInfo?["mode"] as? String ?? "current"
            openSearch(mode: mode)
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                var firstRequestID: UUID?
                var firstEnvironmentID: UUID?
                var failures: [String] = []
                var warnings: [String] = []
                var importedFiles = 0
                var newCollections = 0
                var mergedCollections = 0
                var newRequests = 0
                var mergedRequests = 0
                var newEnvironments = 0
                var mergedEnvironments = 0
                for url in urls {
                    do {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        let imported = try PostmanImporter.parse(data, fallbackName: url.deletingPathExtension().lastPathComponent)
                        for warning in imported.warnings {
                            warnings.append("\(url.lastPathComponent): \(warning)")
                            store.log(L10n.format("Import warning for %@: %@", language: appLanguage,
                                                  url.lastPathComponent, warning), level: "WARN")
                        }
                        var mergedWorkspace = store.workspace
                        let summary = PostmanImporter.merge(imported, into: &mergedWorkspace)
                        let skippedDrafts = RequestDrafts.preserveUnsavedRequests(
                            store.requestDrafts, previous: store.workspace, merged: &mergedWorkspace)
                        store.workspace = mergedWorkspace
                        if skippedDrafts > 0 {
                            let warning = appLanguage == "zh-Hans"
                                ? "已跳过 \(skippedDrafts) 个含未保存草稿的请求；保存草稿后可重新导入。"
                                : "Skipped \(skippedDrafts) requests with unsaved drafts; save them and import again."
                            warnings.append("\(url.lastPathComponent): \(warning)")
                            store.log(L10n.format("Import warning for %@: %@", language: appLanguage,
                                                  url.lastPathComponent, warning), level: "WARN")
                        }
                        let updatedRequests = max(0, summary.updatedRequests - skippedDrafts)
                        importedFiles += 1
                        newCollections += summary.addedCollections
                        mergedCollections += summary.updatedCollections
                        newRequests += summary.addedRequests
                        mergedRequests += updatedRequests
                        newEnvironments += summary.addedEnvironments
                        mergedEnvironments += summary.updatedEnvironments
                        if firstRequestID == nil, let key = imported.collections.first?.requests.first?.importKey {
                            firstRequestID = store.workspace.collections.flatMap(\.requests).first { $0.importKey == key }?.id
                        }
                        if firstEnvironmentID == nil, let key = imported.environments.first?.importKey {
                            firstEnvironmentID = store.workspace.environments.first { $0.importKey == key }?.id
                        }
                        store.log(L10n.format("Imported %@: %d new / %d merged collections, %d new / %d merged requests, %d new / %d merged environments",
                                              language: appLanguage, url.lastPathComponent,
                                              summary.addedCollections, summary.updatedCollections,
                                              summary.addedRequests, updatedRequests,
                                              summary.addedEnvironments, summary.updatedEnvironments))
                    } catch {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                        store.log(L10n.format("Import failed for %@: %@", language: appLanguage,
                                              url.lastPathComponent, error.localizedDescription), level: "ERROR")
                    }
                }
                if let firstRequestID {
                    selectedRequestID = firstRequestID
                    selectedEnvironmentID = nil
                    selectedCollectionID = nil
                    searchContextCollectionID = store.workspace.collections.first { $0.requests.contains(where: { $0.id == firstRequestID }) }?.id
                } else if let firstEnvironmentID {
                    activateEditorTab(.environment(firstEnvironmentID))
                    store.workspace.selectedEnvironmentID = firstEnvironmentID
                }
                revealActiveRequest(selectedRequestID)
                let notices = failures + warnings
                importNoticeTitle = failures.isEmpty
                    ? (warnings.isEmpty ? "Import complete" : "Imported with warnings")
                    : "Some files could not be imported"
                importError = appLanguage == "zh-Hans"
                    ? "已导入 \(importedFiles)/\(urls.count) 个文件。集合：新增 \(newCollections)，合并 \(mergedCollections)；请求：新增 \(newRequests)，合并 \(mergedRequests)；环境：新增 \(newEnvironments)，合并 \(mergedEnvironments)。"
                    : "Imported \(importedFiles)/\(urls.count) files. Collections: \(newCollections) new, \(mergedCollections) merged; requests: \(newRequests) new, \(mergedRequests) merged; environments: \(newEnvironments) new, \(mergedEnvironments) merged."
                if !notices.isEmpty {
                    importError += "\n\n" + notices.prefix(5).joined(separator: "\n")
                    if notices.count > 5 {
                        importError += "\n" + L10n.format("…and %d more notices", language: appLanguage,
                                                          notices.count - 5)
                    }
                }
                showingImportError = true
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return }
                importNoticeTitle = "Import failed"
                importError = error.localizedDescription
                showingImportError = true
                store.log(L10n.format("Import failed: %@", language: appLanguage,
                                      error.localizedDescription), level: "ERROR")
            }
        }
        .alert(LocalizedStringKey(importNoticeTitle), isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError)
        }
        .sheet(isPresented: $showingRenameCollection) {
            RenameDialog(title: "Rename Collection", placeholder: "Collection name", name: $collectionNameDraft) { newName in
                if let id = renamingCollectionID,
                   let index = store.workspace.collections.firstIndex(where: { $0.id == id }) {
                    store.workspace.collections[index].name = newName
                }
            }
        }
        .alert("Delete Collection?", isPresented: $showingDeleteCollection) {
            Button("Delete", role: .destructive) {
                guard let id = deletingCollectionID else { return }
                let removedIDs = Set(store.collection(id)?.requests.map(\.id) ?? [])
                store.workspace.collections.removeAll { $0.id == id }
                closeRemovedRequestTabs(removedIDs)
                if selectedCollectionID == id { selectedCollectionID = nil }
                if let selectedFolderID,
                   !store.workspace.collections.contains(where: { ($0.folders ?? []).contains(where: { $0.id == selectedFolderID }) }) {
                    self.selectedFolderID = nil
                }
                if searchContextCollectionID == id { searchContextCollectionID = nil }
                if searchScopeID == id { searchScopeID = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This collection and its requests will be removed from local storage.")
        }
        .sheet(isPresented: $showingRenameFolder) {
            RenameDialog(title: "Rename Folder", placeholder: "Folder name", name: $folderNameDraft) { newName in
                for ci in store.workspace.collections.indices {
                    if let fi = store.workspace.collections[ci].folders?.firstIndex(where: { $0.id == renamingFolderID }) {
                        store.workspace.collections[ci].folders?[fi].name = newName
                        break
                    }
                }
            }
        }
        .alert("Delete Folder?", isPresented: $showingDeleteFolder) {
            Button("Delete", role: .destructive) {
                if let folderID = deletingFolderID, let collectionID = deletingFolderCollectionID {
                    let previousIDs = Set(store.collection(collectionID)?.requests.map(\.id) ?? [])
                    store.deleteFolder(folderID, from: collectionID)
                    let remainingIDs = Set(store.collection(collectionID)?.requests.map(\.id) ?? [])
                    closeRemovedRequestTabs(previousIDs.subtracting(remainingIDs))
                    if let selectedFolderID,
                       !(store.collection(collectionID)?.folders ?? []).contains(where: { $0.id == selectedFolderID }) {
                        self.selectedFolderID = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The folder, its subfolders, and their requests will be removed.")
        }
        .sheet(isPresented: $showingRenameRequest) {
            RenameDialog(title: "Rename Request", placeholder: "Request name", name: $requestNameDraft) { newName in
                guard let id = renamingRequestID,
                      var request = store.requestDrafts[id] ?? store.request(id) else { return }
                request.name = newName
                store.requestDrafts[id] = request
                saveRequest(id)
            }
        }
        .alert("Delete Request?", isPresented: $showingDeleteRequest) {
            Button("Delete", role: .destructive) {
                guard let id = deletingRequestID else { return }
                store.deleteRequest(id)
                discardAndCloseRequestTab(id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This request will be removed from local storage.")
        }
        .alert("Save changes before closing?", isPresented: $showingUnsavedCloseAlert) {
            Button("Save") {
                guard let id = closingRequestID else { return }
                if saveRequest(id) { discardAndCloseRequestTab(id) }
                closingRequestID = nil
            }
            Button("Discard Changes", role: .destructive) {
                if let id = closingRequestID { discardAndCloseRequestTab(id) }
                closingRequestID = nil
            }
            Button("Cancel", role: .cancel) { closingRequestID = nil }
        } message: {
            Text("Save this request to local storage or discard your edits.")
        }
        .alert("Delete Environment?", isPresented: $showingDeleteEnvironment) {
            Button("Delete", role: .destructive) {
                guard let id = deletingEnvironmentID else { return }
                store.workspace.environments.removeAll { $0.id == id }
                if store.workspace.selectedEnvironmentID == id { store.workspace.selectedEnvironmentID = nil }
                closeEnvironmentTab(id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This environment and its variables will be removed from local storage.")
        }
        .alert("Recover Workspace?", isPresented: $showingWorkspaceRecovery) {
            Button("Back Up and Reset", role: .destructive) {
                do {
                    if let backup = try store.recoverUnreadableWorkspace() {
                        importNoticeTitle = "Workspace recovered"
                        importError = appLanguage == "zh-Hans"
                            ? "原文件已备份为 \(backup.lastPathComponent)。当前工作区已保存。"
                            : "The original file was backed up as \(backup.lastPathComponent). The current workspace is now saved."
                        showingImportError = true
                    }
                } catch {
                    importNoticeTitle = "Recovery failed"
                    importError = error.localizedDescription
                    showingImportError = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original workspace.json will be copied to a backup before the current workspace is saved.")
        }
        .sheet(item: $runnerCollection) { collection in
            CollectionRunnerPane(collection: collection, store: store)
                .frame(minWidth: DialogMetrics.runnerWidth, minHeight: DialogMetrics.runnerHeight)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsPane()
                .frame(width: DialogMetrics.formWidth, height: DialogMetrics.settingsHeight)
        }
    }

    private func openSearch(mode: String) {
        if mode == "global" {
            searchScopeID = nil
            searchReplaceVisible = false
        } else {
            searchScopeID = searchContextCollectionID ?? selectedCollectionID ?? store.workspace.collections.first {
                $0.requests.contains(where: { $0.id == selectedRequestID })
            }?.id
            searchReplaceVisible = mode == "replace"
        }
        searchOpen = true
    }

    private func navigateToSearchHit(_ hit: SearchHit) {
        let address = hit.address
        if let requestID = address.requestID {
            selectedRequestID = requestID
            selectedCollectionID = nil
            selectedEnvironmentID = nil
            selectedFolderID = nil
            if let collectionID = address.collectionID {
                expandedCollectionIDs.insert(collectionID)
                searchContextCollectionID = collectionID
            }
            switch address.kind {
            case "request.preScript": selectedTab = "Scripts"; selectedScriptTab = "Pre-request"
            case "request.postScript": selectedTab = "Scripts"; selectedScriptTab = "Post-response"
            case let kind where kind.hasPrefix("request.param."): selectedTab = "Params"
            case let kind where kind.hasPrefix("request.header."): selectedTab = "Headers"
            case let kind where kind.hasPrefix("request.auth."): selectedTab = "Auth"
            case "request.body", "request.binaryPath", "request.graphqlVariables": selectedTab = "Body"
            default: break
            }
        } else if let folderID = address.folderID {
            selectedFolderID = folderID
            selectedRequestID = nil
            selectedCollectionID = nil
            selectedEnvironmentID = nil
        } else if let environmentID = address.environmentID {
            selectedEnvironmentID = environmentID
            selectedRequestID = nil
            selectedCollectionID = nil
            selectedFolderID = nil
            searchContextCollectionID = nil
        } else if let collectionID = address.collectionID {
            selectedCollectionID = collectionID
            selectedRequestID = nil
            selectedEnvironmentID = nil
            selectedFolderID = nil
            searchContextCollectionID = collectionID
        }
        searchOpen = false
        showHistory = false
    }

    private func replaceSearchHit(_ hit: SearchHit) {
        let count = applySearchReplacement([hit], allOccurrences: false)
        if count > 0 {
            store.log(L10n.format("Replaced 1 match in %@ / %@", language: appLanguage,
                                  hit.context, L10n.string(hit.field, language: appLanguage)))
        }
    }

    private func replaceAllSearchHits(_ hits: [SearchHit]) {
        let count = applySearchReplacement(hits, allOccurrences: true)
        store.log(L10n.format("Replaced %d matches in %@", language: appLanguage, count,
                              L10n.string(searchScopeID == nil ? "workspace" : "collection",
                                          language: appLanguage)))
    }

    private func applySearchReplacement(_ hits: [SearchHit], allOccurrences: Bool) -> Int {
        var working = workspaceWithDrafts
        var count = 0
        for hit in hits {
            count += SearchEngine.replace(hit, in: &working, query: searchQuery,
                                          with: replacement, caseSensitive: searchCaseSensitive,
                                          allOccurrences: allOccurrences)
        }
        guard count > 0 else { return 0 }
        if hits.contains(where: { $0.address.requestID == nil }) {
            var persisted = store.workspace
            for index in persisted.collections.indices {
                guard let changed = working.collections.first(where: { $0.id == persisted.collections[index].id }) else { continue }
                persisted.collections[index].name = changed.name
                persisted.collections[index].variables = changed.variables
                persisted.collections[index].folders = changed.folders
            }
            persisted.environments = working.environments
            store.workspace = persisted
        }
        for id in Set(hits.compactMap { $0.address.requestID }) {
            if let request = working.collections.flatMap(\.requests).first(where: { $0.id == id }) {
                store.requestDrafts[id] = request
            }
        }
        return count
    }

    private var editorTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(openTabs) { tab in
                    switch tab {
                    case .request(let id):
                        if let request = store.request(id) {
                            let displayedRequest = store.requestDrafts[id] ?? request
                            HStack(spacing: 6) {
                                Button { activateEditorTab(tab) } label: {
                                    Text(displayedRequest.method).font(.caption2.monospaced().bold())
                                        .foregroundStyle(methodColor(displayedRequest.method))
                                    Text(displayedRequest.name).lineLimit(1).frame(maxWidth: 130)
                                    if requestHasUnsavedChanges(id) {
                                        Image(systemName: "circle.fill").font(.system(size: 6))
                                            .foregroundStyle(Color.accentColor)
                                            .help(L10n.string("Unsaved changes", language: appLanguage))
                                            .accessibilityLabel(L10n.string("Unsaved changes", language: appLanguage))
                                    }
                                }.buttonStyle(.plain)
                                Button { closeRequestTab(id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .help(L10n.string("Close tab", language: appLanguage))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(selectedRequestID == id && !showHistory && !searchOpen
                                        ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                    case .environment(let id):
                        if let environment = store.environment(id) {
                            HStack(spacing: 6) {
                                Button { activateEditorTab(tab) } label: {
                                    Text(L10n.string("ENV", language: appLanguage))
                                        .font(.caption2.monospaced().bold())
                                        .foregroundStyle(.blue)
                                        .frame(width: 38, alignment: .leading)
                                    Text(environment.name).lineLimit(1).frame(maxWidth: 130)
                                }
                                .buttonStyle(.plain)
                                Button { closeEnvironmentTab(id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .help(L10n.string("Close environment tab", language: appLanguage))
                                .accessibilityLabel(L10n.string("Close environment tab", language: appLanguage))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(selectedEnvironmentID == id && !showHistory && !searchOpen
                                        ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }.padding(.horizontal, 10).padding(.vertical, 5)
        }
        .frame(height: 38)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func activateEditorTab(_ tab: EditorTab?) {
        selectedRequestID = nil
        selectedEnvironmentID = nil
        selectedCollectionID = nil
        selectedFolderID = nil
        showHistory = false
        searchOpen = false
        switch tab {
        case .request(let id):
            selectedRequestID = id
            searchContextCollectionID = store.workspace.collections.first {
                $0.requests.contains(where: { $0.id == id })
            }?.id
        case .environment(let id):
            selectedEnvironmentID = id
            searchContextCollectionID = nil
        case nil: break
        }
    }

    private func closeRequestTab(_ id: UUID) {
        if requestHasUnsavedChanges(id) {
            closingRequestID = id
            showingUnsavedCloseAlert = true
            return
        }
        discardAndCloseRequestTab(id)
    }

    private func discardAndCloseRequestTab(_ id: UUID) {
        store.requestDrafts.removeValue(forKey: id)
        openTabs = EditorTabs.closing(.request(id), in: openTabs)
        openTabs = EditorTabs.available(openTabs, in: store.workspace)
        if selectedRequestID == id { activateEditorTab(openTabs.last) }
    }

    private func closeEnvironmentTab(_ id: UUID) {
        openTabs = EditorTabs.closing(.environment(id), in: openTabs)
        openTabs = EditorTabs.available(openTabs, in: store.workspace)
        if selectedEnvironmentID == id { activateEditorTab(openTabs.last) }
    }

    private func closeRemovedRequestTabs(_ removedIDs: Set<UUID>) {
        for id in removedIDs { store.requestDrafts.removeValue(forKey: id) }
        openTabs = EditorTabs.available(openTabs, in: store.workspace)
        if let selectedRequestID,
           removedIDs.contains(selectedRequestID) || store.request(selectedRequestID) == nil {
            activateEditorTab(openTabs.last)
        }
    }

    private func revealActiveRequest(_ requestID: UUID?) {
        guard let requestID,
              let collection = store.workspace.collections.first(where: { $0.requests.contains(where: { $0.id == requestID }) }),
              let request = collection.requests.first(where: { $0.id == requestID }) else {
            expandedCollectionIDs = []
            expandedFolderIDs = []
            return
        }
        expandedCollectionIDs = [collection.id]
        var ancestors = Set<UUID>()
        var folderID = request.folderID
        while let id = folderID, !ancestors.contains(id),
              let folder = (collection.folders ?? []).first(where: { $0.id == id }) {
            ancestors.insert(id)
            folderID = folder.parentID
        }
        expandedFolderIDs = ancestors
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 4) {
                HStack {
                    Text("PostManage").font(.headline.monospaced())
                    Spacer()
                    Button { sidebarCollapsed = true } label: {
                        Image(systemName: "sidebar.left").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain).help(L10n.string("Collapse sidebar", language: appLanguage))
                    Button { showingSettings = true } label: { Image(systemName: "gearshape").frame(width: 22, height: 22) }
                        .buttonStyle(.plain)
                        .help(L10n.string("Settings", language: appLanguage))
                }
                HStack(spacing: 15) {
                    Button { openSearch(mode: "global") } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.plain).help(L10n.string("Search workspace (⇧⌘F)", language: appLanguage))
                    Button { showHistory = true; searchOpen = false } label: { Image(systemName: "clock.arrow.circlepath") }
                        .buttonStyle(.plain).help(L10n.string("Request history", language: appLanguage))
                    Spacer()
                    Menu {
                        Button("New Collection") {
                            createCollection()
                        }
                        Button("New Environment") {
                            activateEditorTab(.environment(store.addEnvironment()))
                            environmentsCollapsed = false
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                        .menuStyle(.borderlessButton)
                        .help(L10n.string("Create a collection or environment", language: appLanguage))
                        .accessibilityLabel(L10n.string("Create a collection or environment", language: appLanguage))
                    Menu {
                        Button("Import Postman JSON…") { showingImporter = true }
                        Menu("Export Collection") {
                            ForEach(store.workspace.collections) { collection in
                                Button(collection.name) { exportCollection(collection) }
                            }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 22, height: 22) }
                        .menuStyle(.borderlessButton)
                        .help(L10n.string("Import or export Postman files", language: appLanguage))
                        .accessibilityLabel(L10n.string("Import or export Postman files", language: appLanguage))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            GeometryReader { geometry in
                let availableHeight = Double(geometry.size.height)
                let maxCollectionsHeight = max(180.0, availableHeight - 150.0)
                let collectionsHeight = min(max(availableHeight * collectionsPaneFraction, 180.0), maxCollectionsHeight)
                VStack(spacing: 0) {
                    if environmentsCollapsed {
                        collectionsPane.frame(maxHeight: .infinity)
                        Divider()
                    } else {
                        collectionsPane
                            .frame(height: collectionsHeight)
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 1)
                            .frame(height: 9)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    if dragStartCollectionsHeight == nil { dragStartCollectionsHeight = collectionsHeight }
                                    let proposed = min(max((dragStartCollectionsHeight ?? collectionsHeight) + Double(value.translation.height), 180.0), maxCollectionsHeight)
                                    collectionsPaneFraction = proposed / max(availableHeight, 1)
                                }
                                .onEnded { _ in dragStartCollectionsHeight = nil })
                            .onHover { hovering in
                                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                            }
                            .help(L10n.string("Drag to resize sidebar sections", language: appLanguage))
                    }
                    environmentsPane
                        .frame(maxHeight: environmentsCollapsed ? nil : .infinity)
                }
            }
            Divider()
            HStack(spacing: 5) {
                Image(systemName: store.saveError != nil || store.historySaveError != nil
                      ? "exclamationmark.triangle" : unsavedRequestCount > 0 ? "circle.dotted" : "checkmark.circle")
                if let error = store.workspaceLoadError {
                    Text("Workspace needs recovery").help(error)
                    Spacer()
                    Button("Recover…") { showingWorkspaceRecovery = true }.buttonStyle(.borderless)
                } else if let error = store.saveError {
                    Text("Save failed").help(error)
                    Spacer()
                    Button("Retry") { store.retrySave() }.buttonStyle(.borderless)
                } else if let error = store.historySaveError {
                    Text("History save failed").help(error)
                    Spacer()
                    Button("Retry") { store.retrySave() }.buttonStyle(.borderless)
                } else if unsavedRequestCount > 0 {
                    Text(appLanguage == "zh-Hans"
                         ? "\(unsavedRequestCount) 个请求未保存"
                         : "\(unsavedRequestCount) unsaved requests")
                    Spacer()
                    Button("Save All") { store.saveAllRequestDrafts() }
                        .buttonStyle(.borderless)
                        .help(L10n.string("Save all request drafts", language: appLanguage))
                } else {
                    Text("Saved locally")
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(store.saveError != nil || store.historySaveError != nil
                             ? Color.red : unsavedRequestCount > 0 ? Color.accentColor : Color.secondary)
            .padding(12)
        }
    }

    private var collectionsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("COLLECTIONS").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button {
                    createCollection()
                } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help(L10n.string("New Collection", language: appLanguage))
                    .accessibilityLabel(L10n.string("New Collection", language: appLanguage))
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 5)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if store.workspace.collections.isEmpty {
                        Text("No collections yet. Use + to create one or import a Postman file.")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                    ForEach(store.workspace.collections) { collection in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Button {
                                    searchContextCollectionID = collection.id
                                    if expandedCollectionIDs.contains(collection.id) {
                                        expandedCollectionIDs.remove(collection.id)
                                    } else {
                                        expandedCollectionIDs.insert(collection.id)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: expandedCollectionIDs.contains(collection.id) ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .frame(width: 12)
                                        Text(collection.name).fontWeight(.medium).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(L10n.string(expandedCollectionIDs.contains(collection.id)
                                                  ? "Collapse collection" : "Expand collection",
                                                  language: appLanguage))
                                Menu {
                                    Button("Add Request") {
                                        selectedRequestID = store.addRequest(to: collection.id)
                                        selectedEnvironmentID = nil
                                        selectedCollectionID = nil
                                        expandedCollectionIDs.insert(collection.id)
                                        searchContextCollectionID = collection.id
                                    }
                                    Button("Add Folder") {
                                        createFolder(in: collection.id)
                                    }
                                    Button("Paste Request") { pasteRequest(into: collection.id) }
                                        .disabled(requestClipboard == nil)
                                    Divider()
                                    Button("Edit Variables") {
                                        selectedCollectionID = collection.id
                                        selectedRequestID = nil
                                        selectedEnvironmentID = nil
                                    }
                                    Button("Search in Collection") {
                                        searchScopeID = collection.id
                                        searchReplaceVisible = false
                                        searchOpen = true
                                    }
                                    Button("Run Collection…") { runnerCollection = collection }
                                    Button("Rename Collection") { beginRename(collection) }
                                    Button("Export Collection…") { exportCollection(collection) }
                                    Divider()
                                    Button("Delete Collection", role: .destructive) { beginDelete(collection) }
                                } label: { Image(systemName: "ellipsis").frame(width: 19, height: 19) }
                                    .menuStyle(.borderlessButton)
                                    .help(L10n.string("Collection actions", language: appLanguage))
                                    .accessibilityLabel(L10n.string("Collection actions", language: appLanguage))
                            }
                            .padding(.vertical, 2)
                            .contextMenu {
                                Button("Paste Request") { pasteRequest(into: collection.id) }
                                    .disabled(requestClipboard == nil)
                                Divider()
                                Button("Search in Collection") {
                                    searchScopeID = collection.id
                                    searchReplaceVisible = false
                                    searchOpen = true
                                }
                                Button("Run Collection…") { runnerCollection = collection }
                                Button("Edit Variables") {
                                    selectedCollectionID = collection.id
                                    selectedRequestID = nil
                                    selectedEnvironmentID = nil
                                }
                                Button("Rename Collection") { beginRename(collection) }
                                Button("Export Collection…") { exportCollection(collection) }
                                Button("Delete Collection", role: .destructive) { beginDelete(collection) }
                            }
                            .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                                acceptTreeDrop(providers, collectionID: collection.id, target: nil)
                            }
                            if expandedCollectionIDs.contains(collection.id) {
                                VStack(alignment: .leading, spacing: 1) {
                                    collectionItems(collection, parentID: nil)
                                    Button {
                                        selectedRequestID = store.addRequest(to: collection.id)
                                        selectedEnvironmentID = nil
                                        selectedCollectionID = nil
                                        searchContextCollectionID = collection.id
                                    } label: { Label("Add Request", systemImage: "plus").font(.caption.monospaced()) }
                                        .buttonStyle(.plain)
                                        .padding(.vertical, 2)
                                }
                                .padding(.leading, 19)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }

    private func treeEntries(_ collection: RequestCollection, parentID: UUID?) -> [CollectionTreeEntry] {
        let folders = (collection.folders ?? []).filter { $0.parentID == parentID }.map(CollectionTreeEntry.folder)
        let requests = collection.requests.filter { $0.folderID == parentID }.map(CollectionTreeEntry.request)
        return (folders + requests).sorted { $0.order < $1.order }
    }

    private func dropTargetBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { activeDropTargetID == id }, set: { targeted in
            if targeted { activeDropTargetID = id }
            else if activeDropTargetID == id { activeDropTargetID = nil }
        })
    }

    private func pasteRequest(into collectionID: UUID, folderID: UUID? = nil) {
        guard let requestClipboard else { return }
        var workspace = store.workspace
        guard let newID = RequestOperations.paste(requestClipboard, into: collectionID,
                                                  folderID: folderID, workspace: &workspace) else { return }
        store.workspace = workspace
        if requestClipboard.operation == .cut { self.requestClipboard = nil }
        selectedRequestID = newID
        selectedCollectionID = nil
        selectedEnvironmentID = nil
        selectedFolderID = nil
        searchContextCollectionID = collectionID
        showHistory = false
        searchOpen = false
        expandedCollectionIDs.insert(collectionID)
        if let folderID { expandedFolderIDs.insert(folderID) }
    }

    private func duplicateRequest(_ request: RequestItem, in collection: RequestCollection) {
        guard var current = store.collection(collection.id),
              let newID = RequestOperations.duplicate(request.id, in: &current) else { return }
        if let draft = store.requestDrafts[request.id],
           let index = current.requests.firstIndex(where: { $0.id == newID }) {
            let copied = current.requests[index]
            var result = draft
            result.id = newID
            result.importKey = nil
            result.name += " Copy"
            result.params = draft.params.map { var row = $0; row.id = UUID(); return row }
            result.headers = draft.headers.map { var row = $0; row.id = UUID(); return row }
            result.form = draft.form.map { var row = $0; row.id = UUID(); return row }
            result.multipart = draft.multipart?.map { var row = $0; row.id = UUID(); return row }
            result.folderID = copied.folderID
            result.sortOrder = copied.sortOrder
            current.requests[index] = result
        }
        store.updateCollection(current)
        selectedRequestID = newID
        selectedEnvironmentID = nil
        selectedCollectionID = nil
        selectedFolderID = nil
        searchContextCollectionID = collection.id
        if let duplicated = store.request(newID) {
            renamingRequestID = newID
            requestNameDraft = duplicated.name
            DispatchQueue.main.async { showingRenameRequest = true }
        }
    }

    @ViewBuilder private func requestActions(_ request: RequestItem, in collection: RequestCollection) -> some View {
        Button("Duplicate") { duplicateRequest(request, in: collection) }
        Divider()
        Button("Cut") { requestClipboard = RequestClipboardPayload(operation: .cut, sourceID: request.id, snapshot: request) }
        Button("Copy") { requestClipboard = RequestClipboardPayload(operation: .copy, sourceID: request.id, snapshot: request) }
        Button("Rename Request") {
            renamingRequestID = request.id
            requestNameDraft = request.name
            showingRenameRequest = true
        }
        Divider()
        Button("Delete Request", role: .destructive) {
            deletingRequestID = request.id
            showingDeleteRequest = true
        }
    }

    @ViewBuilder private func collectionItems(_ collection: RequestCollection, parentID: UUID?) -> some View {
        ForEach(treeEntries(collection, parentID: parentID)) { entry in
            switch entry {
            case .folder(let folder):
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Button {
                            searchContextCollectionID = collection.id
                            if expandedFolderIDs.contains(folder.id) { expandedFolderIDs.remove(folder.id) }
                            else { expandedFolderIDs.insert(folder.id) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: expandedFolderIDs.contains(folder.id) ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold)).frame(width: 12)
                                Image(systemName: "folder").foregroundStyle(.secondary)
                                Text(folder.name).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .help(L10n.string(expandedFolderIDs.contains(folder.id)
                                              ? "Collapse folder" : "Expand folder",
                                              language: appLanguage))
                        Menu {
                            Button("Add Request") {
                                selectedRequestID = store.addRequest(to: collection.id, folderID: folder.id)
                                selectedFolderID = nil
                                expandedFolderIDs.insert(folder.id)
                            }
                            Button("Add Subfolder") {
                                createFolder(in: collection.id, parentID: folder.id)
                            }
                            Button("Paste Request") { pasteRequest(into: collection.id, folderID: folder.id) }
                                .disabled(requestClipboard == nil)
                            Divider()
                            Button("Edit Variables") {
                                selectedFolderID = folder.id
                                selectedRequestID = nil
                                selectedEnvironmentID = nil
                                selectedCollectionID = nil
                            }
                            Button("Rename Folder") {
                                renamingFolderID = folder.id
                                folderNameDraft = folder.name
                                showingRenameFolder = true
                            }
                            Divider()
                            Button("Delete Folder", role: .destructive) {
                                deletingFolderID = folder.id
                                deletingFolderCollectionID = collection.id
                                showingDeleteFolder = true
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 18, height: 18) }
                            .menuStyle(.borderlessButton)
                            .help(L10n.string("Folder actions", language: appLanguage))
                            .accessibilityLabel(L10n.string("Folder actions", language: appLanguage))
                    }
                    .padding(.vertical, 2)
                    .background(activeDropTargetID == folder.id && draggingTreeItem?.hasPrefix("request:") == true
                                ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(alignment: .top) {
                        if activeDropTargetID == folder.id && draggingTreeItem?.hasPrefix("folder:") == true
                            && draggingTreeItem != "folder:\(folder.id.uuidString)" {
                            Capsule().fill(Color.accentColor).frame(height: 3)
                                .padding(.horizontal, 2).offset(y: -4)
                        }
                    }
                    .onDrag {
                        let item = "folder:\(folder.id.uuidString)"
                        draggingTreeItem = item
                        return NSItemProvider(object: item as NSString)
                    }
                    .onDrop(of: [UTType.plainText], isTargeted: dropTargetBinding(folder.id)) { providers in
                        acceptTreeDrop(providers, collectionID: collection.id, target: .folder(folder))
                    }
                    if expandedFolderIDs.contains(folder.id) {
                        VStack(alignment: .leading, spacing: 1) {
                            AnyView(collectionItems(collection, parentID: folder.id))
                        }.padding(.leading, 17)
                    }
                }
            case .request(let request):
                HStack(spacing: 4) {
                    Button {
                        selectedRequestID = request.id
                        selectedEnvironmentID = nil
                        selectedCollectionID = nil
                        selectedFolderID = nil
                        searchContextCollectionID = collection.id
                        store.response = nil
                        store.lastError = nil
                        showHistory = false
                        searchOpen = false
                    } label: {
                        HStack(spacing: 6) {
                            Text((store.requestDrafts[request.id] ?? request).method).font(.caption2.monospaced().bold())
                                .foregroundStyle(methodColor((store.requestDrafts[request.id] ?? request).method))
                                .frame(width: 38, alignment: .leading)
                            Text((store.requestDrafts[request.id] ?? request).name).lineLimit(1)
                            if requestHasUnsavedChanges(request.id) {
                                Image(systemName: "circle.fill").font(.system(size: 6))
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(selectedRequestID == request.id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    Menu { requestActions(store.requestDrafts[request.id] ?? request, in: collection) } label: {
                        Image(systemName: "ellipsis").frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(L10n.string("Request actions", language: appLanguage))
                    .accessibilityLabel(L10n.string("Request actions", language: appLanguage))
                }
                .overlay(alignment: .top) {
                    if activeDropTargetID == request.id && draggingTreeItem != "request:\(request.id.uuidString)" {
                        Capsule().fill(Color.accentColor).frame(height: 3)
                            .padding(.horizontal, 2).offset(y: -4)
                    }
                }
                .contextMenu {
                    requestActions(store.requestDrafts[request.id] ?? request, in: collection)
                }
                .onDrag {
                    let item = "request:\(request.id.uuidString)"
                    draggingTreeItem = item
                    return NSItemProvider(object: item as NSString)
                }
                .onDrop(of: [UTType.plainText], isTargeted: dropTargetBinding(request.id)) { providers in
                    acceptTreeDrop(providers, collectionID: collection.id, target: .request(request))
                }
            }
        }
    }

    private func acceptTreeDrop(_ providers: [NSItemProvider], collectionID: UUID,
                                target: CollectionTreeEntry?) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let item = object as? String else { return }
            DispatchQueue.main.async {
                guard var collection = store.collection(collectionID) else { return }
                let destination: UUID?
                let before: UUID?
                switch target {
                case .folder(let folder):
                    if item.hasPrefix("request:") {
                        destination = folder.id
                        before = nil
                        expandedFolderIDs.insert(folder.id)
                    } else {
                        destination = folder.parentID
                        before = folder.id
                    }
                case .request(let request):
                    destination = request.folderID
                    before = request.id
                case nil:
                    destination = nil
                    before = nil
                }
                if CollectionOrganizer.move(item, in: &collection, to: destination, before: before) {
                    store.updateCollection(collection)
                }
                draggingTreeItem = nil
                activeDropTargetID = nil
            }
        }
        return true
    }

    private var environmentsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    environmentsCollapsed.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: environmentsCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold)).frame(width: 12)
                        Text("ENVIRONMENTS").font(.caption.monospaced())
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string(environmentsCollapsed ? "Expand environments" : "Collapse environments",
                                  language: appLanguage))
                Spacer()
                Button {
                    activateEditorTab(.environment(store.addEnvironment()))
                    environmentsCollapsed = false
                } label: { Image(systemName: "plus") }.buttonStyle(.plain).help(L10n.string("Add environment", language: appLanguage))
                    .accessibilityLabel(L10n.string("Add environment", language: appLanguage))
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
            if !environmentsCollapsed { ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if store.workspace.environments.isEmpty {
                        Text("No environments. Use + to add one.")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                    ForEach(store.workspace.environments) { environment in
                        Button {
                            activateEditorTab(.environment(environment.id))
                        } label: {
                            HStack {
                                Image(systemName: "globe")
                                Text(environment.name).lineLimit(1)
                                Spacer()
                                if store.workspace.selectedEnvironmentID == environment.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                            .padding(6)
                            .background(selectedEnvironmentID == environment.id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            } }
        }
    }

    private func createCollection() {
        let id = store.addCollection()
        expandedCollectionIDs.insert(id)
        searchContextCollectionID = id
        selectedCollectionID = id
        selectedFolderID = nil
        selectedRequestID = nil
        selectedEnvironmentID = nil
        showHistory = false
        searchOpen = false
        if let collection = store.collection(id) {
            DispatchQueue.main.async { beginRename(collection) }
        }
    }

    private func createFolder(in collectionID: UUID, parentID: UUID? = nil) {
        guard let id = store.addFolder(to: collectionID, parentID: parentID) else { return }
        expandedCollectionIDs.insert(collectionID)
        if let parentID { expandedFolderIDs.insert(parentID) }
        expandedFolderIDs.insert(id)
        searchContextCollectionID = collectionID
        selectedFolderID = id
        selectedCollectionID = nil
        selectedRequestID = nil
        selectedEnvironmentID = nil
        showHistory = false
        searchOpen = false
        renamingFolderID = id
        folderNameDraft = store.collection(collectionID)?.folders?.first(where: { $0.id == id })?.name ??
            L10n.string("New Folder", language: appLanguage)
        DispatchQueue.main.async { showingRenameFolder = true }
    }

    private func beginRename(_ collection: RequestCollection) {
        renamingCollectionID = collection.id
        collectionNameDraft = collection.name
        showingRenameCollection = true
    }

    private func beginDelete(_ collection: RequestCollection) {
        deletingCollectionID = collection.id
        showingDeleteCollection = true
    }

    private func exportCollection(_ collection: RequestCollection) {
        do {
            let data = try PostmanExporter.export(collection)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = collection.name.replacingOccurrences(of: "/", with: "-") + ".postman_collection.json"
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                    store.log(L10n.format("Exported collection %@ to %@", language: appLanguage,
                                          collection.name, url.lastPathComponent))
                } catch {
                    store.log(L10n.format("Export failed: %@", language: appLanguage,
                                          error.localizedDescription), level: "ERROR")
                    importNoticeTitle = "Export failed"
                    importError = error.localizedDescription
                    showingImportError = true
                }
            }
        } catch {
            store.log(L10n.format("Export failed: %@", language: appLanguage,
                                  error.localizedDescription), level: "ERROR")
            importNoticeTitle = "Export failed"
            importError = error.localizedDescription
            showingImportError = true
        }
    }

    private func collectionEditor(_ collection: RequestCollection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(collection.name).font(.title3.monospaced().bold())
            Text("Collection variables are available to its requests. The selected environment can override them.")
                .foregroundStyle(.secondary).font(.caption.monospaced())
            KeyValueEditor(items: Binding(
                get: { store.collection(collection.id)?.variables ?? [] },
                set: { values in
                    if var current = store.collection(collection.id) {
                        current.variables = values
                        store.updateCollection(current)
                    }
                }), title: "Collection variables")
        }
        .padding(16)
    }

    private func folderEditor(_ collection: RequestCollection, folderID: UUID) -> some View {
        let folder = (collection.folders ?? []).first { $0.id == folderID }
        return VStack(alignment: .leading, spacing: 12) {
            Text(collection.name + " / " + collection.folderPath(for: folderID)).font(.title3.monospaced().bold())
            Text("Folder variables override collection variables for requests in this folder.")
                .foregroundStyle(.secondary).font(.caption.monospaced())
            KeyValueEditor(items: Binding(
                get: {
                    guard let current = store.collection(collection.id),
                          let item = current.folders?.first(where: { $0.id == folderID }) else { return [] }
                    return item.variables
                },
                set: { values in
                    if var current = store.collection(collection.id),
                       let index = current.folders?.firstIndex(where: { $0.id == folderID }) {
                        current.folders?[index].variables = values
                        store.updateCollection(current)
                    }
                }), title: "Folder variables")
            if folder == nil { Spacer() }
        }
        .padding(16)
    }

    private func sendRequest(_ request: RequestItem) {
        guard !request.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.send(request)
    }

    private func collectionPath(for request: RequestItem) -> String {
        guard let collection = store.workspace.collections.first(where: { $0.requests.contains(where: { $0.id == request.id }) })
        else { return "Collection" }
        let path = collection.folderPath(for: request)
        return collection.name + (path.isEmpty ? "" : " / " + path)
    }

    private func requestEditor(_ request: Binding<RequestItem>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(collectionPath(for: request.wrappedValue))
                    .font(.title3.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    .help(collectionPath(for: request.wrappedValue))
                Image(systemName: "chevron.right").font(.caption.monospaced()).foregroundStyle(.secondary)
                TextField("Request name", text: request.name)
                    .font(.title3.monospaced().bold()).textFieldStyle(.plain)
                    .frame(minWidth: 150, maxWidth: .infinity)
                if requestHasUnsavedChanges(request.wrappedValue.id) {
                    Image(systemName: "circle.fill").font(.system(size: 7))
                        .foregroundStyle(Color.accentColor)
                        .help(L10n.string("Unsaved changes", language: appLanguage))
                        .accessibilityLabel(L10n.string("Unsaved changes", language: appLanguage))
                }
                environmentPicker
            }
            .padding(16)
            TextField("Request description (optional)", text: Binding(
                get: { request.wrappedValue.descriptionText ?? "" },
                set: { value in request.wrappedValue.descriptionText = value }))
                .font(.caption.monospaced()).textFieldStyle(.plain).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 10)
            Divider()
                .padding(.top, 4)
            HStack(spacing: 8) {
                Picker("", selection: request.method) {
                    ForEach(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"], id: \.self) { Text($0) }
                }
                .labelsHidden().accessibilityLabel(L10n.string("HTTP method", language: appLanguage)).frame(width: 105)
                if showQueryParamsInURL {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(RequestURLPresentation.urlWithParams(request.wrappedValue))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .lineLimit(1)
                    }
                    .frame(height: 27)
                    .padding(.horizontal, 7)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                    .help(L10n.string("URL preview including enabled query parameters; edit the base URL below or use Params", language: appLanguage))
                } else {
                    TextField("Enter request URL, e.g. http://localhost:8080/api", text: request.url)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { sendRequest(request.wrappedValue) }
                }
                if store.sendingRequestID == request.wrappedValue.id {
                    ProgressView().controlSize(.small).accessibilityLabel(L10n.string("Sending…", language: appLanguage))
                }
                Button(L10n.string(store.sendingRequestID == request.wrappedValue.id ? "Sending…" : "Send",
                                   language: appLanguage)) {
                    sendRequest(request.wrappedValue)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.sending || store.runningCollectionID != nil ||
                              request.wrappedValue.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                if store.sending {
                    Button(L10n.string(store.cancellingRequest ? "Cancelling…" : "Cancel",
                                       language: appLanguage)) { store.cancelSend() }
                        .disabled(store.cancellingRequest)
                        .help(L10n.string("Cancel the active request", language: appLanguage))
                }
                Button("Save") { saveRequest(request.wrappedValue.id) }
                    .disabled(!requestHasUnsavedChanges(request.wrappedValue.id))
                    .keyboardShortcut("s", modifiers: .command)
                    .help(L10n.string("Save request to local workspace (⌘S)", language: appLanguage))
            }
            .padding(.horizontal, 16).padding(.top, 16)
            HStack(spacing: 10) {
                Toggle("Show Params in URL", isOn: $showQueryParamsInURL)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                if showQueryParamsInURL {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(RequestURLPresentation.urlWithParams(request.wrappedValue), forType: .string)
                    } label: { Label("Copy URL", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .help(L10n.string("Copy URL with Params", language: appLanguage))
                    TextField("Base URL", text: request.url)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { sendRequest(request.wrappedValue) }
                }
            }
            .font(.caption.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 12)
            Picker("Request section", selection: $selectedTab) {
                ForEach(["Params", "Headers", "Auth", "Body", "Scripts"], id: \.self) { Text(LocalizedStringKey($0)) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16)
            GeometryReader { geometry in
                let availableHeight = Double(geometry.size.height)
                let maxEditorHeight = max(180.0, availableHeight - 170.0)
                let editorHeight = min(max(availableHeight * requestEditorPaneFraction, 180.0), maxEditorHeight)
                VStack(spacing: 0) {
                Group {
                switch selectedTab {
                case "Params": KeyValueEditor(items: request.params, title: "Query parameters")
                        .id("params-\(request.wrappedValue.id)")
                case "Headers": KeyValueEditor(items: request.headers, title: "Request headers")
                        .id("headers-\(request.wrappedValue.id)")
                case "Auth":
                    AuthEditor(auth: Binding(
                        get: { request.wrappedValue.auth ?? AuthConfig() },
                        set: { value in request.wrappedValue.auth = value }))
                case "Body":
                    VStack(alignment: .leading) {
                        Picker("Body type", selection: request.bodyType) {
                            Text("None").tag("none")
                            Text("Raw / JSON").tag("raw")
                            Text("Form URL encoded").tag("form")
                            Text("Multipart form-data").tag("multipart")
                            Text("Binary file").tag("binary")
                            Text("GraphQL").tag("graphql")
                        }
                        .pickerStyle(.radioGroup).horizontalRadioGroupLayout()
                        if request.wrappedValue.bodyType == "raw" {
                            HStack {
                                Picker("Content type", selection: Binding(
                                    get: { request.wrappedValue.rawContentType ?? "application/json" },
                                    set: { value in request.wrappedValue.rawContentType = value })) {
                                    Text("JSON").tag("application/json")
                                    Text("Text").tag("text/plain")
                                    Text("XML").tag("application/xml")
                                    Text("HTML").tag("text/html")
                                }.frame(width: 220)
                                if (request.wrappedValue.rawContentType ?? "application/json").contains("json") {
                                    Button("Format JSON") {
                                        do { request.wrappedValue.body = try JSONFormatting.pretty(request.wrappedValue.body) }
                                        catch {
                                            jsonFormatError = error.localizedDescription
                                            showingJSONFormatError = true
                                        }
                                    }
                                    .help(L10n.string("Format and indent the request JSON", language: appLanguage))
                                }
                            }
                            if (request.wrappedValue.rawContentType ?? "application/json").contains("json") {
                                JSONTextEditor(text: request.body)
                            } else {
                                TextEditor(text: request.body).font(.system(.body, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            }
                        } else if request.wrappedValue.bodyType == "form" {
                            KeyValueEditor(items: request.form, title: "Form fields")
                        } else if request.wrappedValue.bodyType == "multipart" {
                            MultipartEditor(parts: Binding(
                                get: { request.wrappedValue.multipart ?? [] },
                                set: { value in request.wrappedValue.multipart = value }))
                        } else if request.wrappedValue.bodyType == "binary" {
                            HStack {
                                TextField("File path", text: Binding(
                                    get: { request.wrappedValue.binaryPath ?? "" },
                                    set: { value in request.wrappedValue.binaryPath = value }))
                                Button("Browse") {
                                    let panel = NSOpenPanel()
                                    panel.begin { result in
                                        if result == .OK, let url = panel.url { request.wrappedValue.binaryPath = url.path }
                                    }
                                }
                                .help(L10n.string("Choose a local file", language: appLanguage))
                            }
                            Spacer()
                        } else if request.wrappedValue.bodyType == "graphql" {
                            Text("Query").font(.caption.monospaced().bold())
                            TextEditor(text: request.body).font(.system(.body, design: .monospaced))
                            Text("Variables (JSON)").font(.caption.monospaced().bold())
                            TextEditor(text: Binding(
                                get: { request.wrappedValue.graphqlVariables ?? "" },
                                set: { value in request.wrappedValue.graphqlVariables = value }))
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Spacer()
                        }
                    }.padding(16)
                case "Scripts":
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(["Pre-request", "Post-response"], id: \.self) { tab in
                                Button {
                                    selectedScriptTab = tab
                                } label: {
                                    Text(LocalizedStringKey(tab))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(selectedScriptTab == tab ? Color.accentColor.opacity(0.15) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                        .frame(width: 140)
                        .padding(8)
                        Divider()
                        if selectedScriptTab == "Pre-request" {
                            ScriptEditor(text: request.preScript, hint: "Runs before sending. Use pm.request, pm.environment and CryptoJS.HmacSHA256.")
                        } else {
                            ScriptEditor(text: request.postScript, hint: "Runs after the response. Use pm.response.json(), pm.test(), pm.expect().")
                        }
                    }
                default:
                    EmptyView()
                }
            }
                .frame(height: editorHeight)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                    .frame(height: 9)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartEditorHeight == nil { dragStartEditorHeight = editorHeight }
                            let proposed = min(max((dragStartEditorHeight ?? editorHeight) +
                                                   Double(value.translation.height), 180.0), maxEditorHeight)
                            requestEditorPaneFraction = proposed / max(availableHeight, 1)
                        }
                        .onEnded { _ in dragStartEditorHeight = nil })
                    .onHover { hovering in
                        if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .help(L10n.string("Drag to resize request and response", language: appLanguage))
                responsePane.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert("Invalid JSON", isPresented: $showingJSONFormatError) {
            Button("OK", role: .cancel) {}
        } message: { Text(jsonFormatError) }
    }

    private var environmentPicker: some View {
        Picker("Environment", selection: $store.workspace.selectedEnvironmentID) {
            Text("No Environment").tag(nil as UUID?)
            ForEach(store.workspace.environments) { environment in
                Text(environment.name).tag(environment.id as UUID?)
            }
        }
        .frame(width: 210)
    }

    private func environmentEditor(_ environment: Binding<Environment>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Environment name", text: environment.name)
                    .font(.title3.monospaced().bold()).textFieldStyle(.plain)
                Spacer()
                if store.workspace.selectedEnvironmentID == environment.wrappedValue.id {
                    Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Use Environment") { store.workspace.selectedEnvironmentID = environment.wrappedValue.id }
                        .buttonStyle(.borderedProminent)
                }
                Button("Delete", role: .destructive) {
                    let id = environment.wrappedValue.id
                    deletingEnvironmentID = id
                    showingDeleteEnvironment = true
                }
            }
            Text("Use {{variableName}} in URLs, parameters, headers, and body. Script updates are saved here.")
                .foregroundStyle(.secondary).font(.caption.monospaced())
            KeyValueEditor(items: environment.variables, title: "Variables")
        }
        .padding(16)
    }

    private var responsePane: some View {
        ResponsePane(response: selectedRequestID.flatMap { store.responses[$0] },
                     logs: store.logs, error: selectedRequestID.flatMap { store.errors[$0] })
    }

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": .green
        case "DELETE": .red
        case "POST": .orange
        default: .blue
        }
    }
}

private struct WindowFrameMemory: NSViewRepresentable {
    private let name = "PostManageMainWindow"

    func makeNSView(context: Context) -> NSView {
        let view = WindowFrameView()
        view.onWindowChange = configure
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { configure(window) }
    }

    private func configure(_ window: NSWindow) {
        guard window.frameAutosaveName != name else { return }
        _ = window.setFrameUsingName(name)
        window.setFrameAutosaveName(name)
    }
}

private final class WindowFrameView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindowChange?(window) }
    }
}

struct KeyValueEditor: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    @Binding var items: [KVItem]
    let title: String
    @State private var bulkEditing = false
    @State private var bulkText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LocalizedStringKey(title)).font(.caption.monospaced().bold()).foregroundStyle(.secondary)
                if !bulkEditing {
                    Button { items.append(KVItem()) } label: { Label("Add", systemImage: "plus") }
                        .buttonStyle(.borderless)
                        .help(L10n.string("Add one row", language: appLanguage))
                }
                Button(L10n.string(bulkEditing ? "Single Edit" : "Bulk Edit", language: appLanguage)) {
                    if !bulkEditing { bulkText = KVBatchCodec.serialize(items) }
                    bulkEditing.toggle()
                }
                .buttonStyle(.borderless)
                .help(L10n.string(bulkEditing ? "Edit rows individually"
                                  : "Edit one key: value pair per line; prefix // to disable",
                                  language: appLanguage))
                Spacer()
            }
            if bulkEditing {
                Text("One key: value per line. Prefix // to disable a row.")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                TextEditor(text: $bulkText)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: bulkText) { _, value in
                        items = KVBatchCodec.parse(value, existing: items)
                    }
            } else {
                HStack {
                    Text("ON").frame(width: 30)
                    Text("KEY").frame(maxWidth: .infinity, alignment: .leading)
                    Text("VALUE").frame(maxWidth: .infinity, alignment: .leading)
                    Text("").frame(width: 20)
                }.font(.caption.monospaced()).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach($items) { $item in
                            HStack {
                                Toggle("Enabled", isOn: $item.enabled)
                                    .labelsHidden().accessibilityLabel(L10n.string("Enable row", language: appLanguage)).frame(width: 30)
                                TextField("Key", text: $item.key)
                                    .accessibilityLabel(L10n.string("Key", language: appLanguage))
                                TextField("Value", text: $item.value)
                                    .accessibilityLabel(L10n.string("Value", language: appLanguage))
                                Button {
                                    items.removeAll { $0.id == item.id }
                                } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).frame(width: 20)
                                    .help(L10n.string("Remove row", language: appLanguage))
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ScriptEditor: View {
    @Binding var text: String
    let hint: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(hint)).font(.caption.monospaced()).foregroundStyle(.secondary)
            JavaScriptEditor(text: $text)
        }.padding(16)
    }
}

struct AuthEditor: View {
    @Binding var auth: AuthConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authorization").font(.caption.monospaced().bold()).foregroundStyle(.secondary)
            Picker("Authorization type", selection: $auth.type) {
                Text("None").tag("none")
                Text("Bearer Token").tag("bearer")
                Text("Basic Auth").tag("basic")
                Text("API Key").tag("apikey")
            }
            .labelsHidden()
            .frame(width: 260, alignment: .leading)
            switch auth.type {
            case "bearer":
                TextField("Token or {{variable}}", text: $auth.token).frame(maxWidth: 520, alignment: .leading)
            case "basic":
                TextField("Username", text: $auth.username).frame(maxWidth: 520, alignment: .leading)
                SecureField("Password", text: $auth.password).frame(maxWidth: 520, alignment: .leading)
            case "apikey":
                TextField("Key", text: $auth.key).frame(maxWidth: 520, alignment: .leading)
                TextField("Value or {{variable}}", text: $auth.value).frame(maxWidth: 520, alignment: .leading)
                Text("Add to").font(.caption.monospaced().bold()).foregroundStyle(.secondary)
                Picker("API key placement", selection: $auth.placement) {
                    Text("Header").tag("header")
                    Text("Query").tag("query")
                }.labelsHidden().frame(width: 220, alignment: .leading)
            default: EmptyView()
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MultipartEditor: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    @Binding var parts: [MultipartPart]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Multipart fields").font(.caption.monospaced().bold()).foregroundStyle(.secondary)
                Button { parts.append(MultipartPart()) } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .help(L10n.string("Add multipart field", language: appLanguage))
                Spacer()
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($parts) { $part in
                        HStack {
                            Toggle("Enabled", isOn: $part.enabled)
                                .labelsHidden().accessibilityLabel(L10n.string("Enable multipart field", language: appLanguage)).frame(width: 25)
                            TextField("Key", text: $part.key).frame(minWidth: 80)
                            Picker("Multipart field type", selection: $part.kind) {
                                Text("Text").tag("text")
                                Text("File").tag("file")
                            }.labelsHidden().frame(width: 75)
                            if part.kind == "file" {
                                TextField("File path", text: $part.filePath)
                                Button("Browse") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.begin { result in
                                        if result == .OK, let url = panel.url { part.filePath = url.path }
                                    }
                                }
                            } else {
                                TextField("Value", text: $part.value)
                            }
                            Button { parts.removeAll { $0.id == part.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                                .help(L10n.string("Remove multipart field", language: appLanguage))
                        }
                    }
                }
            }
        }
    }
}
