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

    /// The one "Share Screenshot": a picture of these accounts' card — a provider's accounts from its
    /// header's right-click, one account from its caption's — drawn as the dashboard draws them, copied
    /// to the clipboard. On a successful copy it asks the layout store to surface the transient "Copied
    /// to clipboard" pill; a failure beeps and logs instead.
    @discardableResult
    static func share(
        groups: [ProviderGroup],
        dataStore: WidgetDataStore,
        layout: LayoutStore,
        appearance: ColorScheme
    ) -> Bool {
        func line(_ widget: PlacedWidget) -> DashboardLine? {
            guard let descriptor = layout.descriptor(for: widget) else { return nil }
            return DashboardLine(descriptor: descriptor, data: dataStore.data(for: descriptor))
        }
        guard let family = DashboardFamily.make(groups: groups, line: line).first else { return false }
        let plans = Dictionary(uniqueKeysWithValues: family.accounts.compactMap { account in
            dataStore.plan(for: account.id).map { (account.id, $0) }
        })
        guard let image = image(for: ShareCardView(family: family, plans: plans, appearance: appearance)) else {
            AppLog.error(.lifecycle, "share card: ImageRenderer produced no image for \(family.id)")
            NSSound.beep()
            return false
        }
        guard copyToPasteboard(image) else { return false }
        layout.presentShareConfirmation()
        return true
    }
}
