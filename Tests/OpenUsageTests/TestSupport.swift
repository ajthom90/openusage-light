import Foundation
import os
@testable import OpenUsage

final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var response: HTTPResponse
    var requests: [HTTPRequest] = []

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return response
    }
}

final class RoutingHTTPClient: HTTPClient, @unchecked Sendable {
    private let requestsLock = OSAllocatedUnfairLock(initialState: [HTTPRequest]())
    var requests: [HTTPRequest] { requestsLock.withLock { $0 } }
    private let handler: @Sendable (HTTPRequest) async throws -> HTTPResponse

    init(handler: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse) {
        self.handler = handler
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requestsLock.withLock { $0.append(request) }
        return try await handler(request)
    }
}

extension HTTPRequest {
    /// Claude's hourly reset-grants check, which shares the usage endpoint's path.
    var isClaudeResetGrantsCheck: Bool { url.query?.contains("cedar_ember=1") == true }
}

/// A mutable clock so a test can advance `now` between refreshes to exercise time-based gates.
final class TestClock: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Date.distantPast)

    init(_ value: Date) { set(value) }

    var now: Date { lock.withLock { $0 } }

    func set(_ value: Date) { lock.withLock { $0 = value } }
}

/// A thread-safe value a stub HTTP handler can read while the test flips it.
final class TestSwitch<Value: Sendable>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    init(_ value: Value) { lock = OSAllocatedUnfairLock(initialState: value) }

    var value: Value {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

@MainActor
final class TestProviderRuntime: ProviderRuntime {
    let provider: Provider
    let widgetDescriptors: [WidgetDescriptor]
    let snapshot: ProviderSnapshot

    init(provider: Provider, descriptors: [WidgetDescriptor], snapshot: ProviderSnapshot) {
        self.provider = provider
        self.widgetDescriptors = descriptors
        self.snapshot = snapshot
    }

    func refresh() async -> ProviderSnapshot { snapshot }
}

@MainActor
final class CountingProviderRuntime: ProviderRuntime {
    let provider: Provider
    let widgetDescriptors: [WidgetDescriptor]
    let snapshot: ProviderSnapshot
    var refreshCount = 0

    init(provider: Provider, descriptors: [WidgetDescriptor], snapshot: ProviderSnapshot) {
        self.provider = provider
        self.widgetDescriptors = descriptors
        self.snapshot = snapshot
    }

    func refresh() async -> ProviderSnapshot {
        refreshCount += 1
        return snapshot
    }
}

@MainActor
final class HangingProviderRuntime: ProviderRuntime {
    let provider: Provider
    let widgetDescriptors: [WidgetDescriptor]
    private(set) var wasCancelled = false

    init(provider: Provider, descriptors: [WidgetDescriptor]) {
        self.provider = provider
        self.widgetDescriptors = descriptors
    }

    func refresh() async -> ProviderSnapshot {
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            wasCancelled = true
        }
        return ProviderSnapshot.error(provider: provider, message: "hung")
    }
}

@MainActor
final class SequenceProviderRuntime: ProviderRuntime {
    let provider: Provider
    let widgetDescriptors: [WidgetDescriptor]
    private let snapshots: [ProviderSnapshot]
    private(set) var refreshCount = 0

    init(provider: Provider, descriptors: [WidgetDescriptor], snapshots: [ProviderSnapshot]) {
        self.provider = provider
        self.widgetDescriptors = descriptors
        self.snapshots = snapshots
    }

    func refresh() async -> ProviderSnapshot {
        let snapshot = snapshots[min(refreshCount, snapshots.count - 1)]
        refreshCount += 1
        return snapshot
    }
}
