import Foundation

final class ResponseTrace: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var recordedRedirects: [ResponseRedirect] = []
    private var recordedMetrics: URLSessionTaskMetrics?

    var redirects: [ResponseRedirect] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRedirects
    }

    var timings: ResponseTimings? {
        lock.lock()
        let metric = recordedMetrics?.transactionMetrics.last
        lock.unlock()
        guard let metric else { return nil }
        func elapsed(_ start: Date?, _ end: Date?) -> TimeInterval? {
            guard let start, let end else { return nil }
            return max(0, end.timeIntervalSince(start))
        }
        return ResponseTimings(
            dns: elapsed(metric.domainLookupStartDate, metric.domainLookupEndDate),
            connect: elapsed(metric.connectStartDate, metric.connectEndDate),
            tls: elapsed(metric.secureConnectionStartDate, metric.secureConnectionEndDate),
            upload: elapsed(metric.requestStartDate, metric.requestEndDate),
            wait: elapsed(metric.requestEndDate, metric.responseStartDate),
            download: elapsed(metric.responseStartDate, metric.responseEndDate)
        )
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let from = response.url?.absoluteString, let to = request.url?.absoluteString {
            lock.lock()
            recordedRedirects.append(ResponseRedirect(status: response.statusCode, from: from, to: to))
            lock.unlock()
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        recordedMetrics = metrics
        lock.unlock()
    }
}
