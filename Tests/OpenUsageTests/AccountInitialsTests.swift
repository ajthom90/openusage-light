import XCTest
@testable import OpenUsage

final class AccountInitialsTests: XCTestCase {
    func testRobinsAccountsKeepTheNumberThatTellsThemApart() {
        XCTAssertEqual(
            AccountInitials.tags(for: ["Personal", "Attention Machine 1", "Attention Machine 2"]),
            ["P", "A1", "A2"]
        )
        XCTAssertEqual(AccountInitials.tags(for: ["rob@sunstory.com"]), ["R"])
    }

    func testInitialsKeepWholeNumbersAndFitTwoCharacters() {
        XCTAssertEqual(AccountInitials.tags(for: ["AM 1", "AM2"]), ["A1", "A2"])
        XCTAssertEqual(AccountInitials.tags(for: ["Side Project", "first.last@example.com"]), ["SP", "FL"])
        XCTAssertEqual(AccountInitials.tags(for: ["Account 12", "Side Project Alpha"]), ["12", "SP"])
        XCTAssertEqual(AccountInitials.tags(for: ["1", "2"]), ["1", "2"])
        XCTAssertEqual(AccountInitials.tags(for: ["7"]), ["7"])
    }

    func testCollidingTagsShowTheFirstLetterThatDiffers() {
        XCTAssertEqual(AccountInitials.tags(for: ["Work", "Web", "Personal"]), ["WO", "WE", "P"])
        XCTAssertEqual(AccountInitials.tags(for: ["rob@sunstory.com", "rachel@sunstory.com"]), ["RO", "RA"])
        XCTAssertEqual(AccountInitials.tags(for: ["rob@sunstory.com", "robin@sunstory.com"]), ["RS", "RI"])
        XCTAssertEqual(AccountInitials.tags(for: ["rob@sunstory.com", "rob@gmail.com"]), ["RS", "RG"])
    }

    func testIndistinguishableNamesAreNumberedInAccountOrder() {
        XCTAssertEqual(AccountInitials.tags(for: ["Work", "Work"]), ["W1", "W2"])
        XCTAssertEqual(AccountInitials.tags(for: ["Work", "W1", "Work"]), ["W2", "W1", "W3"])
    }

    func testEmojiAreDroppedAndCJKKeepsItsFirstCharacter() {
        XCTAssertEqual(AccountInitials.tags(for: ["🚀 Rocket", "仕事", "個人"]), ["R", "仕", "個"])
        XCTAssertEqual(AccountInitials.tags(for: ["🚀", "🌙", "Personal"]), ["1", "2", "P"])
    }

    func testTagsAreNeverEmptyAndDistinctForAnyNames() {
        let pieces = [
            "Work", "Web", "Attention", "Machine", "AM", "Personal", "Perplexity", "rob", "robin",
            "@sunstory.com", "@gmail.com", "1", "2", "12", "W1", "🚀", "仕事", "仕様", " ", "-", ".",
        ]
        var generator = SplitMix64(seed: 13)
        for _ in 0..<5_000 {
            let count = Int.random(in: 2...6, using: &generator)
            var names: [String] = []
            while names.count < count {
                let length = Int.random(in: 1...4, using: &generator)
                let name = (0..<length).map { _ in pieces.randomElement(using: &generator)! }.joined()
                if !names.contains(name) { names.append(name) }
            }
            let tags = AccountInitials.tags(for: names)
            XCTAssertEqual(Set(tags).count, names.count, "\(names) → \(tags)")
            XCTAssertFalse(tags.contains(""), "\(names) → \(tags)")
            XCTAssertEqual(AccountInitials.tags(for: names), tags)
        }
    }

    @MainActor
    func testStripBadgesOnlyProvidersWithSeveralAccounts() {
        func group(_ id: String, _ label: String) -> ProviderMetrics {
            let provider = Provider(id: id, displayName: "P", icon: .providerMark("claude"), accountLabel: label)
            let sample = WidgetData(title: "Session", icon: provider.icon, kind: .percent, used: 10, limit: 100)
            let descriptor = WidgetDescriptor(id: "\(id).session", providerID: id, metricLabel: "Session", sample: sample)
            return ProviderMetrics(provider: provider, metrics: [descriptor])
        }
        let content = MenuBarContentBuilder.build(
            groups: [
                group("claude@1", "Personal"), group("claude@2", "Attention Machine 1"),
                group("claude@3", "Attention Machine 2"), group("codex@1", "rob@sunstory.com"),
            ],
            data: { $0.sample }
        )
        XCTAssertEqual(content.groups.map(\.badge), ["P", "A1", "A2", nil])
    }
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
