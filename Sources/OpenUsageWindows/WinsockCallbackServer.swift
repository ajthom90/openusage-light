#if os(Windows)
import Foundation
import OpenUsageCore
import WinSDK

/// The Windows listener that receives a sign-in's browser redirect: a TCP socket bound to this PC's
/// loopback address only, so nothing on the network can reach it. What a request means is decided by
/// `OAuthCallbackRequest`, the same code the Mac uses; this only moves the bytes.
final class WinsockCallbackServer: OAuthCallbackServer, @unchecked Sendable {
    static let factory: OAuthCallbackServerFactory = { state, port, path in
        try WinsockCallbackServer(state: state, port: port, path: path)
    }

    let redirectURI: String
    private let listener: SOCKET
    private let state: String
    private let path: String
    private let lock = NSLock()
    private var callbackCode: String?
    private var callbackError: (any Error)?
    private var continuation: CheckedContinuation<String, any Error>?
    private var finished = false

    private static let socketsReady: Bool = {
        var data = WSADATA()
        return WSAStartup(0x0202, &data) == 0
    }()

    private init(state: String, port: UInt16?, path: String) throws {
        guard Self.socketsReady else { throw LoopbackCallbackError.listenerFailed("Windows sockets did not start.") }
        let socketHandle = socket(2, 1, 6)             // AF_INET, SOCK_STREAM, IPPROTO_TCP
        guard socketHandle != ~SOCKET(0) else {
            throw LoopbackCallbackError.listenerFailed("Could not create a socket (error \(WSAGetLastError())).")
        }
        // Refuse to share the port with another program.
        var exclusive: Int32 = 1
        _ = withUnsafePointer(to: &exclusive) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<Int32>.size) {
                setsockopt(socketHandle, 0xFFFF, -5, $0, Int32(MemoryLayout<Int32>.size))   // SOL_SOCKET, SO_EXCLUSIVEADDRUSE
            }
        }
        var address = sockaddr_in()
        address.sin_family = ADDRESS_FAMILY(2)
        address.sin_port = (port ?? 0).bigEndian
        address.sin_addr.S_un.S_addr = UInt32(0x7F00_0001).bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketHandle, $0, Int32(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(socketHandle, 4) == 0 else {
            let code = WSAGetLastError()
            closesocket(socketHandle)
            throw LoopbackCallbackError.listenerFailed("Port \(port.map(String.init) ?? "") is unavailable (error \(code)).")
        }
        var assigned = sockaddr_in()
        var length = Int32(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketHandle, $0, &length) }
        }
        let boundPort = UInt16(bigEndian: assigned.sin_port)

        self.listener = socketHandle
        self.state = state
        self.path = path
        self.redirectURI = "http://localhost:\(boundPort)\(path)"
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "OpenUsage Light sign-in listener"
        thread.start()
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let callbackCode {
                lock.unlock()
                continuation.resume(returning: callbackCode)
            } else if let callbackError {
                lock.unlock()
                continuation.resume(throwing: callbackError)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func cancel() {
        finish(.failure(LoopbackCallbackError.cancelled))
    }

    // MARK: - Serving

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            guard client != ~SOCKET(0) else { return }      // the listener was closed
            if serve(client) { return }
        }
    }

    /// Reads one request and answers it; `true` once the sign-in has its answer.
    private func serve(_ client: SOCKET) -> Bool {
        defer { shutdown(client, 1); closesocket(client) }
        // A browser may open a connection and say nothing; don't wait on it forever.
        var timeout: DWORD = 5_000
        _ = withUnsafePointer(to: &timeout) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<DWORD>.size) {
                setsockopt(client, 0xFFFF, 0x1006, $0, Int32(MemoryLayout<DWORD>.size))   // SOL_SOCKET, SO_RCVTIMEO
            }
        }
        var buffer = [CChar](repeating: 0, count: 16_384)
        let received = recv(client, &buffer, Int32(buffer.count), 0)
        guard received > 0 else { return false }
        let request = String(decoding: buffer.prefix(Int(received)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let outcome = OAuthCallbackRequest.evaluate(request, path: path, state: state)
        let response = OAuthCallbackRequest.response(for: outcome)
        _ = response.withUnsafeBytes { raw in
            send(client, raw.bindMemory(to: CChar.self).baseAddress, Int32(raw.count), 0)
        }
        // A stray request (a favicon, the wrong method) is answered and ignored; the real callback ends it.
        guard outcome.status != 404, outcome.status != 405 else { return false }
        finish(outcome.result)
        return true
    }

    private func finish(_ result: Result<String, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let pending = continuation
        continuation = nil
        if case .success(let code) = result { callbackCode = code }
        if case .failure(let error) = result { callbackError = error }
        lock.unlock()
        closesocket(listener)
        switch result {
        case .success(let code): pending?.resume(returning: code)
        case .failure(let error): pending?.resume(throwing: error)
        }
    }
}
#endif
