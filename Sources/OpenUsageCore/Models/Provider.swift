import Foundation

/// A data source that can register widgets it knows how to feed.
package struct Provider: Identifiable, Hashable {
    package let id: String
    package let displayName: String
    package let icon: IconSource
    package let accountLabel: String?
    /// Per-provider quick links (e.g. "Status Page"), listed in the dashboard card's right-click menu.
    /// Declared inline by each provider; mirrors the legacy Tauri `PluginMeta.links`. Empty by default so
    /// providers without links and the existing `Provider(id:displayName:icon:)` call sites need no change.
    package let links: [ProviderLink]

    package init(id: String, displayName: String, icon: IconSource, accountLabel: String? = nil, links: [ProviderLink] = []) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.accountLabel = accountLabel
        self.links = links
    }

    /// "Claude · AM1": the provider and the account's name, for a menu item or dialog that has one line to
    /// tell accounts of the same provider apart.
    package var fullName: String {
        guard let accountLabel, !accountLabel.isEmpty else { return displayName }
        return "\(displayName) · \(accountLabel)"
    }

    /// Links safe to render: trimmed, non-empty label and URL, and an `http(s)` scheme only. Mirrors the
    /// legacy `visibleLinks` filter so a malformed entry never ships a dead or no-op button.
    package var visibleLinks: [ProviderLink] {
        links.compactMap { link in
            let label = link.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty,
                  !url.isEmpty,
                  url.hasPrefix("https://") || url.hasPrefix("http://") else { return nil }
            return ProviderLink(label: label, url: url)
        }
    }
}

/// One external quick link in a provider card's menu: a label and a URL opened in the default browser.
package struct ProviderLink: Hashable {
    package let label: String
    package let url: String
}
