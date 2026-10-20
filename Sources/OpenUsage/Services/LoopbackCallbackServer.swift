import Foundation
import Network

final class LoopbackCallbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.robinebers.openusage-light.oauth-callback")
    private let state: String
    private let path: String
    private let port: UInt16
    private let lock = NSLock()
    private var callbackCode: String?
    private var callbackError: Error?
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false

    var redirectURI: String { "http://localhost:\(port)\(path)" }

    private init(listener: NWListener, state: String, path: String, port: UInt16) {
        self.listener = listener
        self.state = state
        self.path = path
        self.port = port
    }

    static func start(state: String, port: UInt16? = nil, path: String = "/callback") async throws -> LoopbackCallbackServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: port.map { NWEndpoint.Port(rawValue: $0)! } ?? .any
        )
        let listener = try NWListener(using: parameters)
        let connectionHandler = LoopbackConnectionHandler()
        listener.newConnectionHandler = { connectionHandler.accept($0) }
        return try await withCheckedThrowingContinuation { continuation in
            let completion = ListenerStartCompletion(continuation)
            listener.stateUpdateHandler = { listenerState in
                switch listenerState {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        completion.finish(.failure(LoopbackCallbackError.listenerFailed("No local port was assigned.")))
                        return
                    }
                    let server = LoopbackCallbackServer(listener: listener, state: state, path: path, port: port)
                    connectionHandler.set { [weak server] connection in
                        server?.accept(connection)
                    }
                    completion.finish(.success(server))
                case .failed(let error):
                    completion.finish(.failure(LoopbackCallbackError.listenerFailed(error.localizedDescription)))
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue(label: "com.robinebers.openusage-light.oauth-listener"))
        }
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
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { connection.cancel(); return }
            guard error == nil, let data, let request = String(data: data, encoding: .utf8) else {
                self.reply(connection, status: 400, body: "Sign-in failed.", result: .failure(LoopbackCallbackError.invalidRequest))
                return
            }
            self.handle(request, connection: connection)
        }
    }

    private func handle(_ request: String, connection: NWConnection) {
        guard let line = request.components(separatedBy: "\r\n").first,
              let target = line.split(separator: " ").dropFirst().first,
              line.hasPrefix("GET ") else {
            reply(connection, status: 405, body: "Only GET is supported.", result: .failure(LoopbackCallbackError.invalidRequest))
            return
        }
        guard let url = URL(string: "http://localhost\(target)"), url.path == path else {
            reply(connection, status: 404, body: "Sign-in callback not found.", result: .failure(LoopbackCallbackError.invalidRequest))
            return
        }
        guard URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            reply(connection, status: 400, body: "Sign-in state did not match.", result: .failure(LoopbackCallbackError.stateMismatch))
            return
        }
        if let error = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "error" })?.value {
            reply(connection, status: 400, body: "Sign-in failed.", result: .failure(LoopbackCallbackError.authorization(error)))
            return
        }
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            reply(connection, status: 400, body: "Authorization code was missing.", result: .failure(LoopbackCallbackError.invalidRequest))
            return
        }
        reply(connection, status: 200, body: "Sign-in complete. You may close this page.", result: .success(code))
    }

    private func reply(_ connection: NWConnection, status: Int, body: String, result: Result<String, Error>) {
        finish(result)
        let bodyData = Data("<!doctype html><title>OpenUsage Light</title><p>\(body)</p>".utf8)
        let response = Data(
            "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n".utf8
        ) + bodyData
        connection.send(content: response, completion: .contentProcessed { [listener] _ in
            connection.cancel()
            listener.cancel()
        })
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let pending = continuation
        continuation = nil
        if case .success(let code) = result { callbackCode = code }
        if case .failure(let error) = result { callbackError = error }
        lock.unlock()
        switch result {
        case .success(let code): pending?.resume(returning: code)
        case .failure(let error): pending?.resume(throwing: error)
        }
    }
}

private final class LoopbackConnectionHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (NWConnection) -> Void)?

    func set(_ handler: @escaping @Sendable (NWConnection) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func accept(_ connection: NWConnection) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        guard let handler else {
            connection.cancel()
            return
        }
        handler(connection)
    }
}

private final class ListenerStartCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<LoopbackCallbackServer, Error>?

    init(_ continuation: CheckedContinuation<LoopbackCallbackServer, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<LoopbackCallbackServer, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        switch result {
        case .success(let server): pending.resume(returning: server)
        case .failure(let error): pending.resume(throwing: error)
        }
    }
}

enum LoopbackCallbackError: LocalizedError, Sendable {
    case listenerFailed(String)
    case invalidRequest
    case stateMismatch
    case cancelled
    case authorization(String)

    var errorDescription: String? {
        switch self {
        case .listenerFailed(let detail): "Could not start the sign-in callback: \(detail)"
        case .invalidRequest: "The sign-in callback request was invalid."
        case .stateMismatch: "The sign-in response did not match this request."
        case .cancelled: "Sign-in was cancelled."
        case .authorization(let error): "Authorization failed: \(error)"
        }
    }
}
