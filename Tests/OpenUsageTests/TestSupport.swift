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
