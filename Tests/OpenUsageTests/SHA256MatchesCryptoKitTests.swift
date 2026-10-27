import CryptoKit
import XCTest
@testable import OpenUsageCore

/// The core's hand-written SHA-256 must agree with Apple's on every message length, above all around the
/// padding boundaries (55, 56, 63, 64, 65 bytes), where an off-by-one in padding shows up.
final class SHA256MatchesCryptoKitTests: XCTestCase {
    func testEveryLengthUpToTwoHundredAndOneMore() {
        var generator = SystemRandomNumberGenerator()
        for length in 0...200 {
            let message = (0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            XCTAssertEqual(SHA256.hash(message), Array(CryptoKit.SHA256.hash(data: Data(message))), "length \(length)")
        }
    }
}
