import Foundation

/// URLSessionDataDelegate-based SSE streaming for iOS.
///
/// Using URLSessionDataDelegate instead of URLSession.bytes(for:) because it
/// gives an explicit URLSessionDataTask reference for clean cancellation when
/// the user dismisses the scan view (T10). Delegate callbacks arrive on a private
/// serial queue owned by the URLSession, so lineBuffer and parser are single-threaded.
private let sseLineBufferMaxBytes = 1_048_576

final class IOSScanSession: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    private var lineBuffer = Data()
    private var parser = SSEParser()
    private(set) var dataTask: URLSessionDataTask?

    private init(continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    /// Create a stream + a session handle. Keep the session to call cancel() later.
    /// The `configuration` parameter defaults to `.default`; pass a custom one in tests
    /// to inject MockURLProtocol without a live network connection.
    static func make(
        request: URLRequest,
        configuration: URLSessionConfiguration = .default
    ) -> (stream: AsyncThrowingStream<SSEEvent, Error>, session: IOSScanSession) {
        var created: IOSScanSession!
        let stream = AsyncThrowingStream<SSEEvent, Error> { continuation in
            let session = IOSScanSession(continuation: continuation)
            created = session
            // delegateQueue: nil → URLSession creates its own serial queue
            let urlSession = URLSession(configuration: configuration, delegate: session, delegateQueue: nil)
            session.dataTask = urlSession.dataTask(with: request)
            session.dataTask?.resume()
            continuation.onTermination = { [weak session] _ in session?.cancel() }
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
        // Process delivery chunk segment-by-segment on newline boundaries. The previous
        // approach (append full chunk, check cap, return early) silently dropped valid SSE
        // events that arrived after an oversized pseudo-line in the same chunk.
        var offset = data.startIndex
        while offset < data.endIndex {
            if let newlineIndex = data[offset...].firstIndex(of: UInt8(ascii: "\n")) {
                lineBuffer.append(contentsOf: data[offset..<newlineIndex])
                offset = data.index(after: newlineIndex)
                if lineBuffer.count > sseLineBufferMaxBytes { lineBuffer = Data(); continue }
                var line = String(decoding: lineBuffer, as: UTF8.self)
                if line.hasSuffix("\r") { line.removeLast() }
                if let event = parser.feed(line: line) { continuation.yield(event) }
                lineBuffer = Data()
            } else {
                lineBuffer.append(contentsOf: data[offset...])
                if lineBuffer.count > sseLineBufferMaxBytes { lineBuffer = Data() }
                break
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
            // Flush any remaining bytes (stream ended without a trailing newline).
            if !lineBuffer.isEmpty {
                var line = String(decoding: lineBuffer, as: UTF8.self)
                if line.hasSuffix("\r") { line.removeLast() }
                if let event = parser.feed(line: line) {
                    continuation.yield(event)
                }
                lineBuffer = Data()
            }
            // Flush any pending SSE event if the stream ended without a trailing blank line.
            if let event = parser.feed(line: "") {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
