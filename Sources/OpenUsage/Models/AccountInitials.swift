import Foundation

/// Short account tags for the menu bar, built the way an avatar falls back to initials: the first
/// letter of the first two words ("AM 1" → "A1", "Side Project" → "SP"), or of the only word plus any
/// trailing number ("AM2" → "A2", "Personal" → "P"). An email uses its local part
/// ("rob@sunstory.com" → "R").
enum AccountInitials {
    static func make(_ name: String) -> String {
        let local = name.split(separator: "@", maxSplits: 1).first.map(String.init) ?? name
        let words: [Substring] = local
            .split(whereSeparator: isSeparator)
            .filter { $0.contains(where: isAlphanumeric) }
        guard let word = words.first, let first = word.first(where: isAlphanumeric) else { return "" }
        if words.count >= 2, let second = words[1].first(where: isAlphanumeric) {
            return String([first, second]).uppercased()
        }
        let trailingDigit: String
        if word.allSatisfy(\Character.isNumber) {
            trailingDigit = ""
        } else {
            let digits = word.reversed().prefix(while: \Character.isNumber)
            trailingDigit = digits.last.map { String($0) } ?? ""
        }
        return (String(first) + trailingDigit).uppercased()
    }

    /// Tags for accounts that share a provider, in order. Accounts whose initials collide fall back to
    /// the first two letters of their name ("Work", "Web" → "WO", "WE").
    static func tags(for names: [String]) -> [String] {
        let initials = names.map(make)
        return zip(names, initials).map { name, tag in
            guard initials.filter({ $0 == tag }).count > 1 else { return tag }
            return String(name.filter(isAlphanumeric).prefix(2)).uppercased()
        }
    }

    private static func isAlphanumeric(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || character == "." || character == "-" || character == "_"
    }
}
