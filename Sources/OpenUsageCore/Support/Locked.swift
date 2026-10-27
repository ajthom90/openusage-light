import Foundation

/// A value guarded by a lock, readable and writable from any thread. A portable stand-in for the
/// unfair lock Apple platforms provide.
package final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    package init(initialState: Value) {
        value = initialState
    }

    package func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
