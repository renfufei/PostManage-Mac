import SwiftUI

struct CollectionRunnerPane: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    let collection: RequestCollection
    @ObservedObject var store: AppStore
    @SwiftUI.Environment(\.dismiss) private var dismiss

    private var running: Bool { store.runningCollectionID == collection.id }
    private var failedRequests: Int { store.runResults.filter { $0.error != nil || $0.failedTests > 0 || ($0.status ?? 0) >= 400 }.count }
    private var passedTests: Int { store.runResults.reduce(0) { $0 + $1.passedTests } }
    private var failedTests: Int { store.runResults.reduce(0) { $0 + $1.failedTests } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text((appLanguage == "zh-Hans" ? "运行 " : "Run ") + collection.name).font(.title2.monospaced().bold()).lineLimit(1)
                Spacer()
                Button("Close") { dismiss() }.disabled(running)
                if running {
                    Button(L10n.string(store.cancellingCollection ? "Stopping…" : "Stop",
                                       language: appLanguage)) { store.cancelCollection() }
                        .disabled(store.cancellingCollection)
                        .help(L10n.string("Stop after cancelling the current request", language: appLanguage))
                }
                Button(L10n.string(running ? "Running…" : "Run Collection", language: appLanguage)) {
                    store.runCollection(collection.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(running || store.sending || store.runningCollectionID != nil || collection.requests.isEmpty)
            }
            Text(appLanguage == "zh-Hans"
                 ? "\(collection.requests.count) 个请求 · 使用当前环境按顺序运行"
                 : "\(collection.requests.count) requests · Runs in order using the selected environment")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            if running {
                ProgressView(value: Double(store.runResults.count), total: Double(max(collection.requests.count, 1)))
            }
            if !store.runResults.isEmpty {
                HStack(spacing: 16) {
                    Text(appLanguage == "zh-Hans" ? "请求 \(store.runResults.count)/\(collection.requests.count)" : "\(store.runResults.count)/\(collection.requests.count) requests")
                    Text(appLanguage == "zh-Hans" ? "请求失败 \(failedRequests)" : "\(failedRequests) request failures")
                        .foregroundStyle(failedRequests == 0 ? .green : .red)
                    Text(appLanguage == "zh-Hans" ? "测试通过 \(passedTests)" : "\(passedTests) tests passed")
                    Text(appLanguage == "zh-Hans" ? "测试失败 \(failedTests)" : "\(failedTests) tests failed")
                        .foregroundStyle(failedTests == 0 ? Color.secondary : Color.red)
                }
                .font(.caption.monospaced())
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(store.runResults) { result in
                        HStack {
                            Text(result.requestName).fontWeight(.medium)
                            Spacer()
                            if let status = result.status {
                                Text(String(status)).foregroundStyle(status < 400 ? .green : .red)
                            }
                            if let duration = result.duration {
                                Text("\(Int(duration * 1000)) ms").foregroundStyle(.secondary)
                            }
                            Text("✓ \(result.passedTests)  ✕ \(result.failedTests)")
                                .foregroundStyle(result.failedTests == 0 ? Color.secondary : Color.red)
                        }
                        if let error = result.error {
                            Text(error).font(.caption.monospaced()).foregroundStyle(.red)
                        }
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .environment(\.locale, Locale(identifier: appLanguage))
    }
}
