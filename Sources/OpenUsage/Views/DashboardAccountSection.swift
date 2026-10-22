import SwiftUI

/// One account inside its provider's card: the account line (name, status, the ↺ resets tag, and the
/// plan tag) over every metric line that has data, in the user's order. Nothing here reacts to the
/// pointer: it shows what it shows. Right-click it for the account's menu; the name line drags it.
struct DashboardAccountSection<Line: View>: View {
    let account: DashboardAccount
    var plan: String?
    var notice: String?
    var refreshing = false
    var staleness: StalenessHint?
    /// Wraps the account line, so the dashboard can attach the account's drag gesture to it. Metric
    /// lines drag themselves.
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var line: (DashboardLine) -> Line

    @Environment(AccountRenameStore.self) private var renaming: AccountRenameStore?

    /// Height of the account line.
    static var lineHeight: CGFloat { 24 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle(AnyView(accountLine))
            ForEach(account.lines) { line($0) }
        }
        .padding(.horizontal, DashboardBox.inset)
        .padding(.vertical, DashboardBox.accountPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var accountLine: some View {
        HStack(spacing: 6) {
            name
            status
            Spacer(minLength: 8)
            if let resets = account.resets {
                ResetCountTag(data: resets)
            }
            if let plan {
                PlanTag(plan: plan)
                    .layoutPriority(1)
            }
        }
        .frame(height: Self.lineHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var name: some View {
        if let renaming, let edit = renaming.edit, edit.providerID == account.id {
            InlineRenameField(renaming: renaming, edit: edit)
                .font(.system(size: 13, weight: .medium))
                .fixedSize()
        } else {
            Text(account.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
    }

    /// The account's refresh state. A warning or stale icon explains itself in the account's
    /// right-click menu.
    @ViewBuilder
    private var status: some View {
        if refreshing {
            MotionAwareProgressView(controlSize: .mini)
                .accessibilityLabel("Refreshing")
        } else if let notice {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.notice)
                .accessibilityLabel(notice)
        } else if let staleness {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityLabel(staleness.tooltip)
        }
    }
}

/// The account's plan as a grey capsule at the trailing edge of the account line.
struct PlanTag: View {
    let plan: String

    var body: some View {
        Text(plan)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(.fill.tertiary))
    }
}

/// "↺ 2": the account's available rate-limit resets, as a static tag beside the plan. It takes the
/// color of the soonest expiry (blue, then orange within 7 days, red within 48 hours). The account's
/// right-click menu says when that is and uses a reset.
struct ResetCountTag: View {
    let data: WidgetData

    var body: some View {
        let tint = Self.tint(data.expirySeverity())
        HStack(spacing: 3) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 9, weight: .bold))
            Text("\(data.resetCreditCount)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(tint.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.resetCreditCount == 1 ? "1 reset available" : "\(data.resetCreditCount) resets available")
    }

    private static func tint(_ severity: WidgetData.MeterSeverity?) -> Color {
        switch severity {
        case .critical: Color(nsColor: .systemRed)
        case .warning: Color(nsColor: .systemOrange)
        case .normal, nil: .accentColor
        }
    }
}
