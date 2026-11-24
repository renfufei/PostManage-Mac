import Foundation

enum RequestURLPresentation {
    static func urlWithParams(_ request: RequestItem) -> String {
        let params = request.params.filter { $0.enabled && !$0.key.isEmpty }
        guard !params.isEmpty else { return request.url }

        let parts = request.url.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let beforeFragment = String(parts[0])
        let fragment = parts.count > 1 ? "#" + String(parts[1]) : ""
        let separator = beforeFragment.contains("?") ? (beforeFragment.hasSuffix("?") || beforeFragment.hasSuffix("&") ? "" : "&") : "?"
        let query = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return beforeFragment + separator + query + fragment
    }
}
