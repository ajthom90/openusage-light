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

    /// Orchestrates a Share Screenshot action end to end: resolve the provider's visible rows from the data
    /// store, build the card with the effective appearance, render it, and copy the PNG to the clipboard.
    /// On a successful copy it asks the layout store to surface a transient "Copied to clipboard" pill —
    /// a clipboard write gives no other signal that it landed.
    /// The rows are every enabled metric of the provider, in the order the dashboard shows them.
    @discardableResult
    static func share(
        group: ProviderGroup,
        dataStore: WidgetDataStore,
        layout: LayoutStore,
        appearance: ColorScheme
    ) -> Bool {
        let rows = group.widgets.compactMap { widget -> WidgetData? in
            guard let descriptor = layout.descriptor(for: widget) else { return nil }
            return dataStore.data(for: descriptor)
        }
        let view = ShareCardView(
            provider: group.provider,
            plan: dataStore.plan(for: group.provider.id),
            rows: rows,
            appearance: appearance
        )
        return renderAndCopy(view, label: group.provider.id, layout: layout)
    }

    /// Shared render→copy pipeline for both share actions: rasterizes `view`, copies the PNG, and on a
    /// successful copy surfaces the transient "Copied to clipboard" pill (a clipboard write gives no other
    /// signal). Beeps and logs (naming the card with `label`) on failure, so a failed export is never
    /// silently swallowed. Returns whether the PNG landed on the pasteboard.
    @discardableResult
    private static func renderAndCopy<Card: View>(_ view: Card, label: String, layout: LayoutStore) -> Bool {
        guard let image = image(for: view) else {
            AppLog.error(.lifecycle, "share card: ImageRenderer produced no image for \(label)")
            NSSound.beep()
            return false
        }
        guard copyToPasteboard(image) else { return false }
        layout.presentShareConfirmation()
        return true
    }
}
