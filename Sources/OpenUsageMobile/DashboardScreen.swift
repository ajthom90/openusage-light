import SwiftUI

/// The phone and tablet dashboard: one card per account, in the order saved on the Mac.
public struct DashboardScreen: View {
    let model: MobileModel

    public init(model: MobileModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            List {
                if let message = model.message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                ForEach(model.accounts) { account in
                    Section {
                        ForEach(account.meters) { MeterRow(meter: $0) }
                    } header: {
                        AccountHeader(account: account)
                    }
                }
                if let updated = model.generatedAt {
                    Section { Text(footer(updated)).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Usage")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Show Usage As", selection: Binding(get: { model.choice }, set: { model.setChoice($0) })) {
                            ForEach(DisplayChoice.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label("Show Usage As", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
    }

    private func footer(_ updated: Date) -> String {
        let when = updated.formatted(.relative(presentation: .named))
        return model.source == .sample ? "Example numbers" : "Updated by your Mac \(when)"
    }
}

private struct AccountHeader: View {
    let account: MobileAccount

    var body: some View {
        HStack {
            Text(account.providerName).font(.headline)
            if !account.name.isEmpty { Text(account.name).foregroundStyle(.secondary) }
            Spacer()
            if let plan = account.plan { Text(plan).font(.caption).foregroundStyle(.secondary) }
            if account.isStale { Label("Outdated", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange) }
        }
        .textCase(nil)
    }
}

private struct MeterRow: View {
    let meter: MobileMeter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meter.title)
                Spacer()
                Text(meter.valueText).foregroundStyle(.secondary)
            }
            if let fraction = meter.fraction {
                ProgressView(value: fraction).tint(usageTint(meter.usedFraction ?? fraction))
            }
            if let resetsAt = meter.resetsAt {
                Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
