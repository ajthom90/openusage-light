import SwiftUI

/// One row in the Accounts list (L1), shaped like a Settings row: the drag grip, the provider mark, the
/// provider name with the account's name in secondary text (the same pairing as the dashboard header),
/// and a trailing chevron. Everything but the grip opens the account's detail (L2); the grip only drags.
struct AccountListRow<Handle: View>: View {
    let provider: Provider
    let handle: (AnyView) -> Handle
    var onOpen: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            // Drag handle only — outside the open target so a click on the grip doesn't open L2.
            handle(AnyView(ReorderGrip()))

            // Open target, expanding to fill so the gap before the chevron is clickable too.
            // `onTapGesture` on a content-shaped, full-width view is the reliable way to make the whole
            // area (including the empty spacer) hit-test, where a plain Button's hit area would shrink
            // to its drawn content.
            HStack(spacing: 8) {
                ProviderIcon(source: provider.icon)
                    .frame(width: 18, height: 18)
                Text(provider.displayName)
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                if let accountLabel = provider.accountLabel {
                    Text(accountLabel)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }

            Button(action: onOpen) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(provider.fullName)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, PanelMetrics.controlRowPadding)
    }
}
