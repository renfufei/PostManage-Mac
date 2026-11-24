import Foundation

enum LogExport {
    static func line(_ entry: LogEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "\(formatter.string(from: entry.date)) [\(entry.level)] \(entry.message)"
    }

    static func all(_ entries: [LogEntry]) -> String {
        entries.map(line).joined(separator: "\n")
    }
}
