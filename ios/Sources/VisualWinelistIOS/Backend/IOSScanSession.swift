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

    #if DEBUG
        // t0 is written on the calling actor before dataTask.resume(); all reads occur later on the
        // delegate serial queue after the network round-trip, so the write-before-read ordering is safe.
        var debugT0: Date?
        private var debugFirstChunkRecorded = false
        private var debugWineCount = 0
        private var debugImageCount = 0
        // Incremented on cancel() so Task { @MainActor in } dispatches from a cancelled scan
        // can detect they're stale before writing into the next scan's HUD metrics.
        private(set) var debugGen = 0
    #endif

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
            #if DEBUG
                session.debugT0 = Date()
            #endif
            session.dataTask?.resume()
            continuation.onTermination = { [weak session] _ in session?.cancel() }
        }
        return (stream, created)
    }

    /// Cancel the underlying URLSessionDataTask. Safe to call from any thread or actor.
    func cancel() {
        dataTask?.cancel()
        #if DEBUG
            debugGen &+= 1
        #endif
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
            #if DEBUG
                if let t0 = debugT0 {
                    let ms = Int(Date().timeIntervalSince(t0) * 1000)
                    let gen = debugGen
                    Task { @MainActor [weak self] in
                        guard self?.debugGen == gen else { return }
                        DebugStore.shared.recordUpload(ms: ms)
                    }
                }
            #endif
            completionHandler(.allow)
        case 415:
            continuation.finish(throwing: BackendError.invalidImage)
            completionHandler(.cancel)
        case 503:
            continuation.finish(throwing: BackendError.scannerBusy)
            completionHandler(.cancel)
        default:
            continuation.finish(throwing: BackendError.httpError(http.statusCode))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        #if DEBUG
            if !debugFirstChunkRecorded, let t0 = debugT0 {
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                debugFirstChunkRecorded = true
                let gen = debugGen
                Task { @MainActor [weak self] in
                    guard self?.debugGen == gen else { return }
                    DebugStore.shared.recordTTFB(ms: ms)
                }
            }
        #endif
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
                if let event = parser.feed(line: line) {
                    continuation.yield(event)
                    #if DEBUG
                        recordDebugEvent(event)
                    #endif
                }
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
                    #if DEBUG
                        recordDebugEvent(event)
                    #endif
                }
                lineBuffer = Data()
            }
            // Flush any pending SSE event if the stream ended without a trailing blank line.
            if let event = parser.feed(line: "") {
                continuation.yield(event)
                #if DEBUG
                    recordDebugEvent(event)
                #endif
            }
            continuation.finish()
        }
    }

    #if DEBUG
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            // Use the last transaction — earlier ones may be redirects; the last is
            // the one that delivered the response. Phase dates are optional: a reused
            // TCP connection reports nil DNS/connect dates, which we surface as nil.
            guard let tx = metrics.transactionMetrics.last else { return }
            func ms(_ start: Date?, _ end: Date?) -> Int? {
                guard let start, let end else { return nil }
                return Int(end.timeIntervalSince(start) * 1000)
            }
            let dns = ms(tx.domainLookupStartDate, tx.domainLookupEndDate)
            let tcp = ms(tx.connectStartDate, tx.connectEndDate)
            let request = ms(tx.requestStartDate, tx.requestEndDate)
            let response = ms(tx.responseStartDate, tx.responseEndDate)
            let gen = debugGen
            Task { @MainActor [weak self] in
                guard self?.debugGen == gen else { return }
                DebugStore.shared.recordTransactionMetrics(
                    dns: dns, tcp: tcp, request: request, response: response)
            }
        }

        private func recordDebugEvent(_ event: SSEEvent) {
            guard let t0 = debugT0 else { return }
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let label: String
            switch event {
            case .wine:
                label = "wine[\(debugWineCount)]"
                debugWineCount += 1
            case .image:
                label = "image[\(debugImageCount)]"
                debugImageCount += 1
            case .complete:
                label = "complete"
            case .error:
                label = "error"
            case .ping, .parseError, .notes:
                return
            }
            let gen = debugGen
            Task { @MainActor [weak self] in
                guard self?.debugGen == gen else { return }
                DebugStore.shared.recordEvent(label: label, ms: ms)
            }
        }
    #endif
}
