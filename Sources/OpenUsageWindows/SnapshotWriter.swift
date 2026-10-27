#if os(Windows)
import Foundation
import OpenUsageCore
import WinSDK

/// Draws the popover into an off-screen bitmap and saves it as a BMP file, with no window and no display
/// involved. Used by `--snapshot` to check what the renderer draws.
enum SnapshotWriter {
    static func write(renderer: PopoverRenderer, to url: URL) -> Bool {
        let width = Win32.scale(PopoverRenderer.width, renderer.dpi)
        let height = renderer.contentHeight() + renderer.footerPixels
        guard width > 0, height > 0, let memory = CreateCompatibleDC(nil) else { return false }
        defer { DeleteDC(memory) }

        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = width
        info.bmiHeader.biHeight = -height          // top-down
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        var bits: UnsafeMutableRawPointer?
        guard let bitmap = CreateDIBSection(memory, &info, UINT(DIB_RGB_COLORS), &bits, nil, 0), let bits else { return false }
        defer { DeleteObject(bitmap) }

        let previous = SelectObject(memory, bitmap)
        _ = renderer.draw(on: memory, size: SIZE(cx: width, cy: height), scroll: 0)
        GdiFlush()
        SelectObject(memory, previous)

        let file = BMPFile.data(width: Int(width), height: Int(height), pixels: bits)
        do {
            try file.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// A 32-bit top-down BMP file from raw BGRA pixels.
enum BMPFile {
    static func data(width: Int, height: Int, pixels: UnsafeRawPointer) -> Data {
        let pixelBytes = width * height * 4
        var file = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { file.append(contentsOf: $0) } }
        file.append(contentsOf: [0x42, 0x4D])
        append(UInt32(14 + 40 + pixelBytes)); append(UInt32(0)); append(UInt32(14 + 40))
        append(UInt32(40)); append(Int32(width)); append(Int32(-height))
        append(UInt16(1)); append(UInt16(32)); append(UInt32(0)); append(UInt32(pixelBytes))
        append(Int32(2835)); append(Int32(2835)); append(UInt32(0)); append(UInt32(0))
        file.append(Data(bytes: pixels, count: pixelBytes))
        return file
    }
}
#endif
