import AppKit
import SwiftUI

struct ResponsePane: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    let response: ResponseData?
    let logs: [LogEntry]
    let error: String?

    @State private var tab = "Body"
    @State private var bodyMode = "Pretty"
    @State private var saveError = ""
    @State private var showingSaveError = false

    private var data: Data { response?.rawData ?? Data((response?.body ?? "").utf8) }

    private var jsonObject: Any? {
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private var image: NSImage? {
        guard response?.mimeType?.hasPrefix("image/") == true else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RESPONSE").font(.caption.monospaced().bold()).foregroundStyle(.secondary)
                if let response {
                    Text("\(response.status) \(response.statusText)")
                        .foregroundStyle(response.status < 400 ? .green : .red)
                    Text("\(Int(response.duration * 1000)) ms · \(response.size) B")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Response section", selection: $tab) {
                    ForEach(["Body", "Headers", "Cookies", "Timing", "Logs"], id: \.self) { Text(LocalizedStringKey($0)) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 390)
            }
            if tab == "Logs" {
                logView
            } else if let response {
                switch tab {
                case "Body": bodyView(response)
                case "Headers": headerView(response)
                case "Cookies": cookieView(response)
                default: timingView(response)
                }
            } else if let error {
                ContentUnavailableView("Request failed", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No response yet", systemImage: "arrow.down.circle",
                                       description: Text("Send a request to see its response."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .environment(\.locale, Locale(identifier: appLanguage))
        .alert("Save failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError)
        }
    }

    private func bodyView(_ response: ResponseData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("View", selection: $bodyMode) {
                    Text("Pretty").tag("Pretty")
                    Text("Raw").tag("Raw")
                    if jsonObject != nil { Text("JSON Tree").tag("Tree") }
                    if image != nil { Text("Image").tag("Image") }
                    Text("Hex").tag("Hex")
                }
                .frame(width: 190)
                Spacer()
                if jsonObject != nil {
                    Button("Format JSON") { bodyMode = "Pretty" }
                        .help(L10n.string("Show formatted response JSON", language: appLanguage))
                }
                Button("Save Body…") { saveBody(response) }
                    .disabled(data.isEmpty)
            }
            Group {
                if bodyMode == "Tree", let object = jsonObject {
                    ScrollView {
                        JSONValueView(name: "root", value: object)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if (bodyMode == "Image" || bodyMode == "Pretty"), let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    if jsonObject != nil && bodyMode != "Hex" {
                        JSONTextEditor(text: .constant(displayText(response)), editable: false)
                    } else {
                        ScrollView {
                            Text(displayText(response))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
        }
    }

    private func displayText(_ response: ResponseData) -> String {
        if bodyMode == "Hex" || (bodyMode == "Pretty" && jsonObject == nil && !isText(response)) {
            return hexPreview(data)
        }
        if bodyMode == "Pretty", let object = jsonObject,
           let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: formatted, encoding: .utf8) {
            return text
        }
        return response.body
    }

    private func isText(_ response: ResponseData) -> Bool {
        let mime = response.mimeType ?? ""
        return mime.hasPrefix("text/") || mime.contains("json") || mime.contains("xml") ||
               mime.contains("javascript") || mime.contains("graphql")
    }

    private func hexPreview(_ data: Data) -> String {
        let bytes = Array(data.prefix(4096))
        let lines = stride(from: 0, to: bytes.count, by: 16).map { offset -> String in
            let chunk = bytes[offset..<min(offset + 16, bytes.count)]
            let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = chunk.map { $0 >= 32 && $0 < 127 ? String(UnicodeScalar($0)) : "." }.joined()
            return String(format: "%08X", offset) + "  " + hex.padding(toLength: 47, withPad: " ", startingAt: 0) + "  " + ascii
        }
        return lines.joined(separator: "\n") + (data.count > 4096
            ? "\n" + L10n.string("… showing first 4096 bytes", language: appLanguage) : "")
    }

    private func headerView(_ response: ResponseData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(response.headers.enumerated()), id: \.offset) { _, header in
                    HStack(alignment: .top) {
                        Text(header.0).fontWeight(.medium).frame(width: 200, alignment: .leading)
                        Text(header.1).textSelection(.enabled)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cookieView(_ response: ResponseData) -> some View {
        Group {
            if response.cookies.isEmpty {
                ContentUnavailableView("No response cookies", systemImage: "circle.dotted")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(response.cookies) { cookie in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cookie.name).fontWeight(.medium)
                                Text(cookie.value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                Text("\(cookie.domain)\(cookie.path)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func timingView(_ response: ResponseData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                timingRow("Total", response.duration)
                if let timings = response.timings {
                    timingRow("DNS", timings.dns)
                    timingRow("Connect", timings.connect)
                    timingRow("TLS", timings.tls)
                    timingRow("Upload", timings.upload)
                    timingRow("Server wait", timings.wait)
                    timingRow("Download", timings.download)
                }
                if let finalURL = response.finalURL {
                    Text(L10n.string("Final URL", language: appLanguage) + ": " + finalURL)
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
                if !response.redirects.isEmpty {
                    Divider()
                    Text("Redirects").font(.headline.monospaced())
                    ForEach(response.redirects) { redirect in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(redirect.status) · \(redirect.from)").font(.caption.monospaced())
                            Text("→ \(redirect.to)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }.textSelection(.enabled)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timingRow(_ label: String, _ duration: TimeInterval?) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).frame(width: 100, alignment: .leading)
            Text(duration.map { "\(Int($0 * 1000)) ms" } ?? "—")
                .font(.system(.body, design: .monospaced))
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if logs.contains(where: { $0.message.contains("[REDACTED]") }) {
                    Label("[REDACTED] hides a sensitive value in the log; the request uses its original value.",
                          systemImage: "lock.shield")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy All Logs") { copyLogs(LogExport.all(Array(logs.reversed()))) }
                    .disabled(logs.isEmpty)
                    .help(L10n.string("Copy all visible log entries", language: appLanguage))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(logs.reversed()) { entry in
                        HStack(alignment: .top) {
                            Text(entry.date, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
                            Text(entry.level).foregroundStyle(entry.level == "ERROR" ? .red : .secondary)
                            Text(entry.message).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button { copyLogs(LogExport.line(entry)) } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n.string("Copy this log entry", language: appLanguage))
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func copyLogs(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveBody(_ response: ResponseData) {
        let panel = NSSavePanel()
        let extensionName: String
        switch response.mimeType {
        case "application/json": extensionName = "json"
        case "image/png": extensionName = "png"
        case "image/jpeg": extensionName = "jpg"
        case "image/gif": extensionName = "gif"
        default: extensionName = isText(response) ? "txt" : "bin"
        }
        panel.nameFieldStringValue = "response." + extensionName
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                saveError = error.localizedDescription
                showingSaveError = true
            }
        }
    }
}

private struct JSONValueView: View {
    let name: String
    let value: Any

    var body: some View {
        if let object = value as? [String: Any] {
            DisclosureGroup("\(name) { \(object.count) }") {
                ForEach(object.keys.sorted(), id: \.self) { key in
                    JSONValueView(name: key, value: object[key]!)
                }
            }
        } else if let array = value as? [Any] {
            DisclosureGroup("\(name) [ \(array.count) ]") {
                ForEach(array.indices, id: \.self) { index in
                    JSONValueView(name: "[\(index)]", value: array[index])
                }
            }
        } else {
            HStack(alignment: .top) {
                Text(name + ":").foregroundStyle(.secondary)
                Text(String(describing: value)).textSelection(.enabled)
            }
            .font(.system(.body, design: .monospaced))
        }
    }
}
