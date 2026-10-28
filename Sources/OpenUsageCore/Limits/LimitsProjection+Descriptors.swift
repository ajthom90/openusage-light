
package extension LimitsProjection.Entry {
    /// An account's entry, with the snapshot lines named by the account's dashboard rows.
    package init(account: Account, snapshot: ProviderSnapshot?, descriptors: [WidgetDescriptor]) {
        let prefix = account.cardID.count + 1
        self.init(
            account: account,
            snapshot: snapshot,
            metricLabels: Dictionary(
                descriptors.map { (String($0.id.dropFirst(prefix)), $0.metricLabel) },
                uniquingKeysWith: { first, _ in first }
            ),
            titles: Dictionary(
                descriptors.map { (String($0.id.dropFirst(prefix)), $0.title) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }
}
