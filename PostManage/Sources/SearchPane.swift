import SwiftUI

extension Notification.Name {
    static let postManageSearch = Notification.Name("PostManageSearch")
}

struct SearchPane: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    let workspace: Workspace
    @Binding var query: String
    @Binding var replacement: String
    @Binding var collectionID: UUID?
    @Binding var caseSensitive: Bool
    @Binding var showReplace: Bool
    let onNavigate: (SearchHit) -> Void
    let onReplace: (SearchHit) -> Void
    let onReplaceAll: ([SearchHit]) -> Void
    let onClose: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var confirmReplaceAll = false

    private var hits: [SearchHit] {
        SearchEngine.find(in: workspace, query: query, collectionID: collectionID, caseSensitive: caseSensitive)
    }

    private var matchCount: Int { hits.reduce(0) { $0 + $1.occurrences } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search").font(.title2.monospaced().bold())
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help(L10n.string("Close search", language: appLanguage))
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search names, URLs, fields, bodies, scripts…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(L10n.string("Clear search", language: appLanguage))
                }
            }
            .padding(9)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))

            HStack {
                Picker("Scope", selection: $collectionID) {
                    Text("All Collections & Environments").tag(nil as UUID?)
                    ForEach(workspace.collections) { collection in
                        Text(collection.name).tag(collection.id as UUID?)
                    }
                }
                .frame(maxWidth: 350)
                Toggle("Match case", isOn: $caseSensitive)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(L10n.string(showReplace ? "Hide Replace" : "Replace", language: appLanguage)) {
                    showReplace.toggle()
                }
                    .buttonStyle(.borderless)
            }

            if showReplace {
                HStack {
                    TextField("Replace with", text: $replacement)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.format("Replace All (%d)", language: appLanguage, matchCount)) {
                        confirmReplaceAll = true
                    }
                        .disabled(matchCount == 0)
                }
            }

            Divider()
            HStack {
                Text(query.isEmpty
                     ? L10n.string("Enter a search term", language: appLanguage)
                     : L10n.format(matchCount == 1 ? "%d match in %d fields" : "%d matches in %d fields",
                                   language: appLanguage, matchCount, hits.count))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text(LocalizedStringKey(collectionID == nil ? "Workspace" : "Current collection"))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if hits.isEmpty {
                ContentUnavailableView(LocalizedStringKey(query.isEmpty ? "Search your workspace" : "No matches"),
                                       systemImage: "magnifyingglass",
                                       description: Text(LocalizedStringKey(query.isEmpty ? "Use ⌘F for this collection or ⇧⌘F for everything." : "Try another term or scope.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(hits) { hit in
                            HStack(spacing: 10) {
                                Button { onNavigate(hit) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(hit.context).fontWeight(.medium).lineLimit(1)
                                        Text(L10n.string(hit.field, language: appLanguage) + " · " + hit.preview)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if hit.occurrences > 1 {
                                    Text("×\(hit.occurrences)").font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                if showReplace {
                                    Button("Replace") { onReplace(hit) }
                                        .buttonStyle(.bordered)
                                }
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
        .padding(18)
        .environment(\.locale, Locale(identifier: appLanguage))
        .onAppear { searchFocused = true }
        .alert(L10n.format("Replace %d matches?", language: appLanguage, matchCount),
               isPresented: $confirmReplaceAll) {
            Button("Replace All", role: .destructive) { onReplaceAll(hits) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.string(collectionID == nil
                             ? "This updates matching fields in the workspace."
                             : "This updates matching fields in this collection.",
                             language: appLanguage))
        }
    }
}
