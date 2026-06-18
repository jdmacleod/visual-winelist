import Foundation

/// URLSessionDataDelegate-based SSE streaming for iOS.
///
/// Using URLSessionDataDelegate instead of URLSession.bytes(for:) because it
/// gives an explicit URLSessionDataTask reference for clean cancellation when
/// the user dismisses the scan view (T10). Delegate callbacks arrive on a private
/// serial queue owned by the URLSession, so lineBuffer and parser are single-threaded.
final class IOSScanSession: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    private var lineBuffer = ""
    private var parser = SSEParser()
    private(set) var dataTask: URLSessionDataTask?

    private init(continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    /// Create a stream + a session handle. Keep the session to call cancel() later.
    static func make(
        request: URLRequest
    ) -> (stream: AsyncThrowingStream<SSEEvent, Error>, session: IOSScanSession) {
        var created: IOSScanSession!
        let stream = AsyncThrowingStream<SSEEvent, Error> { continuation in
            let s = IOSScanSession(continuation: continuation)
            created = s
            // delegateQueue: nil → URLSession creates its own serial queue
            let urlSession = URLSession(configuration: .default, delegate: s, delegateQueue: nil)
            s.dataTask = urlSession.dataTask(with: request)
            s.dataTask?.resume()
        }
        return (stream, created)
    }

    /// Cancel the underlying URLSessionDataTask. Safe to call from any thread or actor.
    func cancel() {
        dataTask?.cancel()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            continuation.finish(throwing: BackendError.unreachable(""))
            completionHandler(.cancel)
            return
        }
        switch http.statusCode {
        case 200:
            completionHandler(.allow)
        case 503:
            continuation.finish(throwing: BackendError.scannerBusy)
            completionHandler(.cancel)
        default:
            continuation.finish(throwing: BackendError.httpError(http.statusCode))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lineBuffer += chunk
        // Split on newlines; keep any partial final line in the buffer
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            if let event = parser.feed(line: line) {
                continuation.yield(event)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled {
                continuation.finish()  // user-initiated cancel: clean end, not an error
            } else {
                continuation.finish(throwing: error)
            }
        } else {
            continuation.finish()
        }
    }
}
