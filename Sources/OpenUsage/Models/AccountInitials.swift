import Foundation

/// Short account tags for the menu-bar badge, unique among one provider's accounts.
///
/// 1. Initials keep numbers, like Discord's guild acronym: the first letter of each word plus every
///    whole number ("Attention Machine 1" → "AM1", "AM2" → "A2"). An email uses its local part.
/// 2. The badge fits two characters, so a longer acronym keeps its first letter and the trailing
///    number that tells it apart ("AM1" → "A1"), or else its first two letters.
/// 3. Accounts whose tags still match swap in the first letter that no other match shares at that
///    position, the way editor tabs show the part of a path that differs ("Work", "Web" → "WO", "WE").
/// 4. Anything still shared, such as the same name twice, gets a numbered tag in account order
///    ("W1", "W2").
enum AccountInitials {
    private static let budget = 2

    static func tags(for names: [String]) -> [String] {
        let letters = names.map(alphanumerics)
        var tags = names.map { fitted(acronym($0)) }

        for group in clashes(in: tags) {
            for index in group {
                let others = group.filter { $0 != index }.map { letters[$0] }
                if let tag = distinguishing(letters[index], from: others) { tags[index] = tag }
            }
        }

        let renumbered = Set(clashes(in: tags).joined()).union(tags.indices.filter { tags[$0].isEmpty })
        var taken = Set(tags.indices.filter { !renumbered.contains($0) }.map { tags[$0] })
        for index in tags.indices where renumbered.contains(index) {
            let initial = letters[index].first.map(String.init) ?? ""
            let tag = (1...).lazy.map { initial + String($0) }.first { !taken.contains($0) }!
            tags[index] = tag
            taken.insert(tag)
        }
        return tags
    }

    private static func acronym(_ name: String) -> String {
        let local = name.split(separator: "@", maxSplits: 1).first.map(String.init) ?? name
        return words(in: local)
            .map { $0.allSatisfy(\.isNumber) ? String($0) : String($0.first!) }
            .joined()
            .uppercased()
    }

    private static func fitted(_ acronym: String) -> String {
        guard acronym.count > budget else { return acronym }
        let number = String(acronym.reversed().prefix(while: \.isNumber).reversed())
        if !number.isEmpty {
            let lettered = String(acronym.first!) + number
            if lettered.count <= budget { return lettered }
            if number.count <= budget { return number }
        }
        return String(acronym.prefix(budget))
    }

    /// The name's first character and its first later character that none of the others has at the
    /// same position, or nil when every character is shared.
    private static func distinguishing(_ letters: [Character], from others: [[Character]]) -> String? {
        guard let first = letters.first else { return nil }
        let position = letters.indices.dropFirst().first { index in
            others.allSatisfy { index >= $0.count || $0[index] != letters[index] }
        }
        return position.map { String(first) + String(letters[$0]) }
    }

    private static func clashes(in tags: [String]) -> [[Int]] {
        Dictionary(grouping: tags.indices) { tags[$0] }
            .values
            .filter { $0.count > 1 }
            .sorted { $0[0] < $1[0] }
    }

    /// Runs of letters and runs of digits, split at separators and wherever letters meet digits
    /// ("AM2" → "AM", "2"). Emoji and punctuation are dropped.
    private static func words(in text: String) -> [Substring] {
        var words: [Substring] = []
        var start: String.Index?
        var previousIsNumber = false
        for index in text.indices {
            let character = text[index]
            let isAlphanumeric = character.isLetter || character.isNumber
            if let wordStart = start, !isAlphanumeric || character.isNumber != previousIsNumber {
                words.append(text[wordStart..<index])
                start = nil
            }
            if isAlphanumeric, start == nil { start = index }
            previousIsNumber = character.isNumber
        }
        if let start { words.append(text[start...]) }
        return words
    }

    private static func alphanumerics(_ name: String) -> [Character] {
        Array(name.uppercased().filter { $0.isLetter || $0.isNumber })
    }
}
