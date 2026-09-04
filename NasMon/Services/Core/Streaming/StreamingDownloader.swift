//
//  StreamingDownloader.swift
//  NasMon
//
//  Created by Brian Li on 8/5/26.
//
//  Delegate-based progressive downloader used by the preview system and the
//  media streaming data source.
//
//  Unlike `URLSession.download(from:)` (which buffers the whole file and only
//  delivers it at the end), this streams received chunks straight to a file
//  on disk and reports progress, so callers can render data as it arrives.
//
//  Supports:
//    - byte-offset resume: pass `writeOffset` > 0 and the file is appended to
//      (the caller must first truncate the destination to that offset);
//    - cancellation via task cancellation.
//

import Foundation

/// Streams a URLSession data task's response body to a file on disk with
/// progress callbacks.
final class StreamingDownloader: NSObject, @unchecked Sendable {

    // MARK: - Configuration

    private let request: URLRequest
    private let destination: URL
    /// Byte offset at which writing begins (0 = truncate and write from start).
    private let writeOffset: Int64
    private let expectedSize: Int64?
    private let onProgress: @Sendable (Int64, Int64?) -> Void

    // MARK: - State

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var received: Int64 = 0
    private var continuation: CheckedContinuation<Int64, Error>?
    private let lock = NSLock()

    init(
        request: URLRequest,
        destination: URL,
        writeOffset: Int64 = 0,
        expectedSize: Int64? = nil,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void
    ) {
        self.request = request
        self.destination = destination
        self.writeOffset = writeOffset
        self.expectedSize = expectedSize
        self.onProgress = onProgress
    }

    // MARK: - Start / Cancel

    /// Run the download, finishing when the response is fully received or an
    /// error occurs. Returns the number of bytes written.
    func start() async throws -> Int64 {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        // Prepare the destination file.
        do {
            try prepareDestination()
        } catch {
            session.invalidateAndCancel()
            throw error
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                // If cancellation arrived before the continuation was set
                // (the onCancel handler already ran and found nil), resume
                // here so the caller never hangs.
                if Task.isCancelled {
                    cancel()
                    return
                }
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            cancel()
        }
    }

    /// Cancel the in-flight download (thread-safe; safe to call more than once).
    func cancel() {
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    /// Number of bytes received so far.
    var bytesReceived: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    // MARK: - Private

    /// Open the destination file: truncate when starting at 0, otherwise
    /// append at `writeOffset` (caller pre-truncated the file).
    private func prepareDestination() throws {
        let fm = FileManager.default
        if writeOffset > 0 {
            guard fm.fileExists(atPath: destination.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let handle = try FileHandle(forUpdating: destination)
            try handle.seek(toOffset: UInt64(writeOffset))
            fileHandle = handle
            received = writeOffset
        } else {
            // Truncate any stale partial file and write from the start.
            try? fm.removeItem(at: destination)
            fm.createFile(atPath: destination.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: destination)
            received = 0
        }
    }

    private func finish(_ result: Result<Int64, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        // Close the file handle on success/error (best effort).
        if let handle = fileHandle {
            try? handle.close()
        }
        fileHandle = nil
        session?.invalidateAndCancel()
        session = nil

        switch result {
        case .success(let bytes):
            continuation?.resume(returning: bytes)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

// MARK: - URLSessionDataDelegate

extension StreamingDownloader: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Same self-signed-cert trust policy as DSMClient.
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            finish(.failure(DSMClientError.fileStationFailed(code: http.statusCode)))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !data.isEmpty else { return }
        do {
            try fileHandle?.write(contentsOf: data)
            lock.lock()
            received += Int64(data.count)
            let received = self.received
            lock.unlock()
            onProgress(received, expectedSize)
        } catch {
            task?.cancel()
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            lock.lock()
            let received = self.received
            lock.unlock()
            finish(.success(received))
        }
    }
}
