#if os(Windows)
import Foundation
import WinSDK

/// The tray icon, drawn at run time: three horizontal usage meters (full, two thirds, a third) in blue on
/// a grey track, on a transparent background so it reads on both light and dark taskbars. Drawn here so
/// the program needs no icon resource file.
enum TrayIcon {
    static func make(dpi: Int) -> HICON? {
        let side = max(16, Int(GetSystemMetricsForDpi(Int32(SM_CXSMICON), UINT(dpi))))
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = Int32(side)
        info.bmiHeader.biHeight = -Int32(side)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        var bits: UnsafeMutableRawPointer?
        guard let color = CreateDIBSection(nil, &info, UINT(DIB_RGB_COLORS), &bits, nil, 0), let bits else { return nil }
        defer { DeleteObject(color) }
        guard let mask = CreateBitmap(Int32(side), Int32(side), 1, 1, nil) else { return nil }
        defer { DeleteObject(mask) }

        let pixels = bits.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let size = Double(side)
        let margin = size * 0.12
        let barHeight = (size - margin * 2) * 0.26
        let gap = ((size - margin * 2) - barHeight * 3) / 2
        let fills = [1.0, 0.66, 0.34]
        let track: (r: Double, g: Double, b: Double) = (150, 150, 158)
        let blue: (r: Double, g: Double, b: Double) = (10, 132, 255)

        for y in 0..<side {
            for x in 0..<side {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                var red = 0.0, green = 0.0, blueChannel = 0.0, alpha = 0.0
                for (row, fill) in fills.enumerated() {
                    let top = margin + Double(row) * (barHeight + gap)
                    let centerY = top + barHeight / 2
                    let trackWidth = size - margin * 2
                    let trackCoverage = coverage(px, py, centerX: margin + trackWidth / 2, centerY: centerY, halfWidth: trackWidth / 2, halfHeight: barHeight / 2)
                    let fillWidth = trackWidth * fill
                    let fillCoverage = coverage(px, py, centerX: margin + fillWidth / 2, centerY: centerY, halfWidth: fillWidth / 2, halfHeight: barHeight / 2)
                    if trackCoverage > 0 {
                        let a = trackCoverage * 0.85
                        (red, green, blueChannel, alpha) = over(track, a, red, green, blueChannel, alpha)
                    }
                    if fillCoverage > 0 {
                        (red, green, blueChannel, alpha) = over(blue, fillCoverage, red, green, blueChannel, alpha)
                    }
                }
                let at = (y * side + x) * 4
                // Premultiplied BGRA.
                pixels[at] = UInt8(max(0, min(255, blueChannel * alpha)))
                pixels[at + 1] = UInt8(max(0, min(255, green * alpha)))
                pixels[at + 2] = UInt8(max(0, min(255, red * alpha)))
                pixels[at + 3] = UInt8(max(0, min(255, alpha * 255)))
            }
        }
        var icon = ICONINFO(fIcon: true, xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color)
        return CreateIconIndirect(&icon)
    }

    /// How much of the pixel a fully rounded bar covers (a signed-distance edge, one pixel soft).
    private static func coverage(_ px: Double, _ py: Double, centerX: Double, centerY: Double, halfWidth: Double, halfHeight: Double) -> Double {
        let radius = min(halfHeight, halfWidth)
        let qx = abs(px - centerX) - (halfWidth - radius)
        let qy = abs(py - centerY) - (halfHeight - radius)
        let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
        let distance = outside + min(max(qx, qy), 0) - radius
        return max(0, min(1, 0.5 - distance))
    }

    /// Source-over compositing of one colour onto the running colour (straight, not premultiplied).
    private static func over(
        _ source: (r: Double, g: Double, b: Double), _ sourceAlpha: Double,
        _ r: Double, _ g: Double, _ b: Double, _ alpha: Double
    ) -> (Double, Double, Double, Double) {
        let outAlpha = sourceAlpha + alpha * (1 - sourceAlpha)
        guard outAlpha > 0 else { return (0, 0, 0, 0) }
        func mix(_ s: Double, _ d: Double) -> Double { (s * sourceAlpha + d * alpha * (1 - sourceAlpha)) / outAlpha }
        return (mix(source.r, r), mix(source.g, g), mix(source.b, b), outAlpha)
    }
}
#endif
