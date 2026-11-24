import SwiftUI

struct HistoryPane: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    let entries: [HistoryEntry]
    let availableRequestIDs: Set<UUID>
    let onOpen: (HistoryEntry) -> Void
    let onClear: () -> Void

    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Request History").font(.title2.monospaced().bold())
                Spacer()
                Button("Clear History") { confirmClear = true }
                    .disabled(entries.isEmpty)
            }
            Text("Recent sends are stored on this Mac. Open an entry to return to its request.")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            Divider()
            if entries.isEmpty {
                ContentUnavailableView("No requests yet", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Text(entry.method).font(.caption.monospaced().bold())
                                    .foregroundStyle(methodColor(entry.method))
                                    .frame(width: 55, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.collectionName + " / " + entry.requestName).fontWeight(.medium)
                                    Text(entry.url).font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary).lineLimit(1)
                                    if let error = entry.error {
                                        Text(error).font(.caption.monospaced()).foregroundStyle(.red).lineLimit(2)
                                    } else if entry.passedTests + entry.failedTests > 0 {
                                        Text(appLanguage == "zh-Hans"
                                             ? "通过 \(entry.passedTests) · 失败 \(entry.failedTests)"
                                             : "\(entry.passedTests) passed · \(entry.failedTests) failed")
                                            .font(.caption.monospaced()).foregroundStyle(entry.failedTests == 0 ? .green : .red)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(entry.date, format: .dateTime.month().day().hour().minute().second())
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    if let status = entry.status {
                                        Text(String(status)).foregroundStyle(status < 400 ? .green : .red)
                                    }
                                    if let duration = entry.duration {
                                        Text("\(Int(duration * 1000)) ms").font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                                Button("Open") { onOpen(entry) }
                                    .disabled(!availableRequestIDs.contains(entry.requestID))
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
        .padding(18)
        .environment(\.locale, Locale(identifier: appLanguage))
        .alert("Clear request history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { onClear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local history list. Collections and requests stay available.")
        }
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
