import Foundation

enum KVBatchCodec {
    static func serialize(_ items: [KVItem]) -> String {
        items.filter { !$0.key.isEmpty || !$0.value.isEmpty }.map { item in
            (item.enabled ? "" : "// ") + item.key + ": " + item.value
        }.joined(separator: "\n")
    }

    static func parse(_ text: String, existing: [KVItem] = []) -> [KVItem] {
        var used = Set<UUID>()
        return text.components(separatedBy: .newlines).compactMap { raw -> KVItem? in
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let enabled = !line.hasPrefix("//")
            if !enabled { line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(pieces[0]).trimmingCharacters(in: .whitespaces)
            let value = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : ""
            guard !key.isEmpty else { return nil }
            var item = existing.first { $0.key == key && !used.contains($0.id) } ?? KVItem()
            item.enabled = enabled
            item.key = key
            item.value = value
            used.insert(item.id)
            return item
        }
    }
}
