import XCTest
@testable import OpenUsageCore

final class SHA256Tests: XCTestCase {
    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    func testStandardVectors() {
        XCTAssertEqual(hex(SHA256.hash([])), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hex(SHA256.hash(Array("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(
            hex(SHA256.hash(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }

    func testAMillionBytes() {
        XCTAssertEqual(
            hex(SHA256.hash([UInt8](repeating: UInt8(ascii: "a"), count: 1_000_000))),
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
        )
    }

    func testPKCEChallengeMatchesRFC7636() {
        XCTAssertEqual(
            PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testGeneratedPairsAreUniqueAndConsistent() {
        let first = PKCE.generate(), second = PKCE.generate()
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertEqual(first.challenge, PKCE.challenge(for: first.verifier))
        XCTAssertEqual(first.verifier.count, 43, "32 random bytes, base64url without padding")
    }
}
