import Foundation

/// The machine-facing limits document the `openusage` command prints (`openusage.limits.v1`).
///
/// It carries only what the provider APIs reported — stable scalars with explicit units, never UI rows,
/// colours, or credentials. Foundation-only, so a non-Apple build can emit and read the same document.
package struct LimitsEnvelope: Codable, Equatable, Sendable {
    package static let schema = "openusage.limits.v1"

    package var schema: String = Self.schema
    package var generatedAt: Date
    /// Account card ids in the user's saved dashboard order. `providers` is keyed (and a JSON object
    /// has no order), so this is what a consumer follows to list accounts the way the dashboard does.
    package var order: [String]
    package var providers: [String: Provider]
    package var errors: [Failure]

    package struct Provider: Codable, Equatable, Sendable {
        /// The provider family (`claude`, `codex`, …) the account belongs to.
        package var provider: String
        package var displayName: String
        /// The account's name as shown on the dashboard.
        package var account: String
        package var plan: String?
        package var fetchedAt: Date
        /// `fetchedAt` plus the refresh interval: when the value stops being served as fresh.
        package var expiresAt: Date
        package var stale: Bool
        package var resources: [String: Resource]
    }

    package struct Resource: Codable, Equatable, Sendable {
        package enum Kind: String, Codable, Sendable { case consumption, balance }

        package var kind: Kind
        package var unit: String
        /// Consumption so far (`consumption` only).
        package var used: Double?
        package var limit: Double?
        package var remaining: Double?
        /// `used / limit`, 0...1 (bounded consumption only).
        package var utilization: Double?
        /// What is left to spend (`balance` only).
        package var available: Double?
        package var resetsAt: Date?
        package var windowSeconds: Int?
        /// When each currently available reset expires, for resources that list them.
        package var expiries: [Date]?
        /// The name the dashboard shows for this reading ("Other Models"), when it has one. Optional and
        /// display-only: scripts should key on the resource's own key, which never changes.
        package var label: String?
    }

    package struct Failure: Codable, Equatable, Sendable {
        package var providerId: String
        package var message: String

        package init(providerId: String, message: String) {
            self.providerId = providerId
            self.message = message
        }
    }

    /// The document as JSON: sorted keys so the same data always prints the same bytes, ISO-8601
    /// timestamps with milliseconds, and no escaped slashes.
    package func json(pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { encoder.outputFormatting.insert(.prettyPrinted) }
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(OpenUsageISO8601.string(from: date))
        }
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// Reads a document written by `json(pretty:)`. A document of another schema is refused rather than
    /// guessed at, so a newer producer never shows up as wrong numbers on an older reader.
    package static func decode(_ data: Data) throws -> LimitsEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = OpenUsageISO8601.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO-8601 date: \(text)"))
            }
            return date
        }
        let envelope = try decoder.decode(LimitsEnvelope.self, from: data)
        guard envelope.schema == Self.schema else { throw DecodeError.unsupportedSchema(envelope.schema) }
        return envelope
    }

    package enum DecodeError: Error, Equatable {
        case unsupportedSchema(String)
    }
}
