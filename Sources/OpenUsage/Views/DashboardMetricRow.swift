import SwiftUI

/// One metric on one row inside an account: its label in the panel's label column, then its mark in the
/// slot the column leaves — a capacity bar, or a value right-aligned where a bar would end. Under the
/// pointer the bar gives way to the row's reading in the same slot, the longest candidate that fits
/// ("64% left · resets in 2h 41m"), and a value reads primary; the row's height never changes.
struct DashboardMetricRow: View {
    let model: DashboardRowModel
    let labelWidth: CGFloat
    /// Whether the pointer is on the row.
    var hovered = false

    var body: some View {
        HStack(spacing: DashboardGrid.columnGap) {
            Text(model.label)
                .font(.body)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            slot
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DashboardGrid.inset)
        .frame(height: DashboardGrid.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var slot: some View {
        switch model.mark {
        case .bar(let fill, let severity):
            if hovered {
                reading
            } else {
                UsageMeterBar(fill: fill, severity: severity)
            }
        case .value(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(hovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// The reading, as the longest of its candidates that fits the slot.
    private var reading: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(model.hoverCandidates.enumerated()), id: \.offset) { _, spans in
                Self.text(spans)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// One line of hover text: the value in Body semibold, the rest in Subheadline; tinted runs take the
    /// severity's colour, the value reads primary and the rest secondary otherwise.
    static func text(_ spans: [DashboardRowModel.Span]) -> Text {
        spans.enumerated().reduce(Text("")) { line, item in
            let (index, span) = item
            let piece = Text(index == 0 ? span.text : " " + span.text)
            let styled: Text
            switch span.role {
            case .value:
                styled = piece.font(.body.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(span.tint.map { Theme.severityColor($0) } ?? Color.primary)
            case .unit, .note:
                styled = piece.font(.subheadline).monospacedDigit()
                    .foregroundStyle(span.tint.map { Theme.severityColor($0) } ?? Color.secondary)
            }
            return line + styled
        }
    }
}
