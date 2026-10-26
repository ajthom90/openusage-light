import AppKit
import SwiftUI

/// Renders a `ShareCardView` into a PNG and copies it to the clipboard. Mirrors `MenuBarStripRenderer`'s
/// `ImageRenderer` → `cgImage` → `NSImage` path (×4 for a crisp, large export), then PNG-encodes it and
/// writes it to the pasteboard.
@MainActor
enum ShareCardRenderer {
    /// Off-screen render scale. ×4 turns the popover-scale card into a crisp, large PNG — a 360pt card
    /// ships as a 1440px image — without authoring a separate large-format layout.
    static let scale: CGFloat = 4

    /// The card rendered to an `NSImage`, or `nil` if `ImageRenderer` produces no CGImage. The image's
    /// point size is the card's natural (flexible) size; its pixel size is that times `scale`.
    static func image<Card: View>(for view: Card) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        )
    }

    /// PNG-encodes an `NSImage`, or `nil` if the bitmap can't be formed.
    static func pngData(from image: NSImage) -> Data? {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes the card's PNG onto the general pasteboard (replacing its contents). Beeps and logs if the
    /// PNG can't be encoded or the pasteboard rejects it, so a failed copy isn't silently swallowed.
    /// Returns `true` only when the PNG actually landed on the pasteboard, so callers can gate a success
    /// confirmation on it (and not claim "copied" when nothing was written).
    @discardableResult
    static func copyToPasteboard(_ image: NSImage) -> Bool {
        guard let png = pngData(from: image) else {
            AppLog.error(.lifecycle, "share card: failed to encode PNG for clipboard")
            NSSound.beep()
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else {
            AppLog.error(.lifecycle, "share card: pasteboard rejected the PNG")
            NSSound.beep()
            return false
        }
        return true
    }

    /// Rasterizes the card and copies the PNG to the clipboard. Beeps and logs on failure, so a failed
    /// export is never silently swallowed. Returns whether the PNG landed on the pasteboard; the caller
    /// shows its own confirmation, since a clipboard write gives no other signal.
    @discardableResult
    static func copy(_ card: ShareCardView) -> Bool {
        guard let image = image(for: card) else {
            AppLog.error(.lifecycle, "share card: ImageRenderer produced no image for \(card.family.id)")
            NSSound.beep()
            return false
        }
        return copyToPasteboard(image)
    }

    /// The right-click and footer "Share Screenshot" action for one account: the account alone under its
    /// provider's header, as the dashboard shows it, with the panel's label column. On a successful copy
    /// it asks the layout store to surface the transient "Copied to clipboard" pill.
    @discardableResult
    static func share(
        group: ProviderGroup,
        dataStore: WidgetDataStore,
        layout: LayoutStore,
        appearance: ColorScheme
    ) -> Bool {
        func line(_ widget: PlacedWidget) -> DashboardLine? {
            guard let descriptor = layout.descriptor(for: widget) else { return nil }
            return DashboardLine(descriptor: descriptor, data: dataStore.data(for: descriptor))
        }
        guard let family = DashboardFamily.make(groups: [group], line: line).first else { return false }
        let card = ShareCardView(
            family: family,
            plans: dataStore.plan(for: group.provider.id).map { [group.provider.id: $0] } ?? [:],
            labelWidth: DashboardGrid.labelWidth(for: DashboardFamily.make(groups: layout.displayGroups, line: line)),
            appearance: appearance
        )
        guard copy(card) else { return false }
        layout.presentShareConfirmation()
        return true
    }
}
