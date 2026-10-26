import SwiftUI

/// What ends a provider's header line. At rest it is the provider's 16 pt logo. While the pointer is
/// anywhere on the provider it is a camera.viewfinder button in the same box: resting on it lifts it on a
/// plate and shows "Copy Screenshot" after the hover dwell, and a click copies an image of the provider's
/// header and card to the clipboard and shows a green check for 1.5 s.
struct DashboardCopyButton: View {
    let provider: Provider
    /// Whether the pointer is on the provider.
    let active: Bool
    /// Copies the image; returns whether it landed on the clipboard.
    let copy: () -> Bool

    @Environment(\.popoverPartyMode) private var partyMode
    @State private var hovered = false
    @State private var copied = false
    @State private var checkTask: Task<Void, Never>?

    static let checkDuration: Duration = .seconds(1.5)
    private static let plateSize: CGFloat = 22

    var body: some View {
        ZStack {
            if copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.positive)
                    .accessibilityLabel("Copied")
            } else if active {
                button
            } else {
                ProviderIcon(source: provider.icon, inset: 0.04)
                    .partyPulse(partyMode)
            }
        }
        .frame(width: DashboardGrid.iconSize, height: DashboardGrid.iconSize)
        .onDisappear { checkTask?.cancel() }
    }

    private var button: some View {
        Button {
            guard copy() else { return }
            copied = true
            checkTask?.cancel()
            checkTask = Task {
                try? await Task.sleep(for: Self.checkDuration)
                guard !Task.isCancelled else { return }
                copied = false
            }
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 14))
                .foregroundStyle(hovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: DashboardGrid.iconSize, height: DashboardGrid.iconSize)
                .background {
                    if hovered {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.fill.tertiary)
                            .frame(width: Self.plateSize, height: Self.plateSize)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .hoverTooltip("Copy Screenshot")
        .accessibilityLabel("Copy Screenshot")
    }
}
