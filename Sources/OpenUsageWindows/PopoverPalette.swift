#if os(Windows)
import OpenUsageCore
import WinSDK

/// The popover's colours, in the Windows light or dark theme.
struct PopoverPalette {
    let background: COLORREF
    let divider: COLORREF
    let track: COLORREF
    let text: COLORREF
    let secondaryText: COLORREF
    let normal: COLORREF
    let warning: COLORREF
    let critical: COLORREF
    let notice: COLORREF

    static func current() -> PopoverPalette {
        Win32.appsUseDarkTheme() ? dark : light
    }

    static let light = PopoverPalette(
        background: Win32.color(249, 249, 249), divider: Win32.color(229, 229, 229), track: Win32.color(226, 226, 230),
        text: Win32.color(28, 28, 30), secondaryText: Win32.color(110, 110, 115),
        normal: Win32.color(10, 132, 255), warning: Win32.color(255, 149, 0), critical: Win32.color(255, 59, 48),
        notice: Win32.color(201, 107, 0)
    )

    static let dark = PopoverPalette(
        background: Win32.color(36, 36, 38), divider: Win32.color(62, 62, 66), track: Win32.color(70, 70, 74),
        text: Win32.color(245, 245, 247), secondaryText: Win32.color(160, 160, 168),
        normal: Win32.color(64, 156, 255), warning: Win32.color(255, 159, 10), critical: Win32.color(255, 69, 58),
        notice: Win32.color(255, 159, 10)
    )

    func color(for severity: WidgetData.MeterSeverity) -> COLORREF {
        switch severity {
        case .normal: normal
        case .warning: warning
        case .critical: critical
        }
    }
}
#endif
