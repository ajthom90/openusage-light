import SwiftUI

/// The popover under a hovered row: the account's resets, soonest first, as a timeline. Each node is a
/// dot on a hairline rail, its title ("Session resets", "Weekly, Fable reset"), when ("Today 5:50 PM ·
/// in 3h 50m") and, on a red run-out node, how long before the reset it hits. The hovered metric's nodes
/// read semibold.
struct AccountResetsPopover: View {
    /// "Codex · sam@hey.com".
    let title: String
    let nodes: [AccountResetsTimeline.Node]
    /// Reports whether the cursor is inside the popover, so the row keeps it open while the cursor
    /// travels from the row into the popover, and closes once it leaves both.
    var onHoverChange: (Bool) -> Void

    private static let width: CGFloat = 250
    private static let dotSize: CGFloat = 8
    /// Where the dot's centre sits from the top of its node: on the title's first line.
    private static let dotCenterY: CGFloat = 7.5
    private static let nodeSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text("Resets, soonest first")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    HStack(alignment: .top, spacing: 10) {
                        rail(for: node, isFirst: index == 0, isLast: index == nodes.count - 1)
                        content(node)
                            .padding(.bottom, index == nodes.count - 1 ? 0 : Self.nodeSpacing)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onContinuousHover { phase in
            switch phase {
            case .active: onHoverChange(true)
            case .ended: onHoverChange(false)
            }
        }
    }

    /// The dot in the rail column, with the hairline running through it from the node above to the one
    /// below: a fixed top segment and a stretchy bottom one, hidden at the ends.
    private func rail(for node: AccountResetsTimeline.Node, isFirst: Bool, isLast: Bool) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(.quaternary).frame(width: 1.5).frame(height: Self.dotCenterY)
                    .opacity(isFirst ? 0 : 1)
                Rectangle().fill(.quaternary).frame(width: 1.5).frame(maxHeight: .infinity)
                    .opacity(isLast ? 0 : 1)
            }
            Circle()
                .fill(Theme.severityColor(node.severity))
                .frame(width: Self.dotSize, height: Self.dotSize)
                .padding(.top, Self.dotCenterY - Self.dotSize / 2)
        }
        .frame(width: Self.dotSize)
        .accessibilityHidden(true)
    }

    private func content(_ node: AccountResetsTimeline.Node) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(node.title)
                .font(node.emphasized ? .callout.weight(.semibold) : .callout)
                .foregroundStyle(node.severity == .critical ? AnyShapeStyle(Theme.severityColor(.critical)) : AnyShapeStyle(.primary))
                .lineLimit(1)
            Text(node.when)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            if let runway = node.runway {
                Text(runway)
                    .font(.subheadline)
                    .foregroundStyle(Theme.severityColor(.critical))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
