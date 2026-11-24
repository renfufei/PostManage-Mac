import Foundation

enum HistorySanitizer {
    static func url(_ raw: String) -> String {
        let pattern = #"(?i)([?&](?:access[_-]?token|refresh[_-]?token|token|api[_-]?key|apikey|app[_-]?key|secret|signature|password|passwd|authorization|awsaccesskeyid)=)[^&#]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "$1••••")
    }
}
