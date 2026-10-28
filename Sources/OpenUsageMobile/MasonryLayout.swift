import SwiftUI

/// Where each card goes when cards are packed into columns: each one into the column that is shortest so far
/// (the leftmost on a tie), so short cards stack instead of leaving holes under them. Cards keep their saved
/// order; only which column they sit in is decided here.
enum MasonryPlacement {
    struct Slot: Equatable {
        let column: Int
        let y: CGFloat
    }

    static func place(heights: [CGFloat], columns: Int, spacing: CGFloat) -> (slots: [Slot], height: CGFloat) {
        guard columns > 0 else { return ([], 0) }
        var bottoms = [CGFloat](repeating: 0, count: columns)
        var slots: [Slot] = []
        for height in heights {
            let column = bottoms.indices.min { (bottoms[$0], $0) < (bottoms[$1], $1) } ?? 0
            let y = bottoms[column] == 0 ? 0 : bottoms[column] + spacing
            slots.append(Slot(column: column, y: y))
            bottoms[column] = y + height
        }
        return (slots, bottoms.max() ?? 0)
    }
}

/// Packs its children into columns of equal width, measuring each child at that width.
struct MasonryLayout: Layout {
    var columns: Int
    var columnGap: CGFloat
    var rowSpacing: CGFloat

    private func columnWidth(for width: CGFloat) -> CGFloat {
        max((width - columnGap * CGFloat(columns - 1)) / CGFloat(columns), 0)
    }

    private func heights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let placed = MasonryPlacement.place(
            heights: heights(subviews, width: columnWidth(for: width)), columns: columns, spacing: rowSpacing
        )
        return CGSize(width: width, height: placed.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = columnWidth(for: bounds.width)
        let placed = MasonryPlacement.place(heights: heights(subviews, width: width), columns: columns, spacing: rowSpacing)
        for (subview, slot) in zip(subviews, placed.slots) {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(slot.column) * (width + columnGap), y: bounds.minY + slot.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: nil)
            )
        }
    }
}
