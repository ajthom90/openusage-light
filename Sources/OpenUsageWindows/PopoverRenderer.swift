#if os(Windows)
import Foundation
import OpenUsageCore
import WinSDK

/// Draws the dashboard into a device context with plain GDI. It knows nothing about windows: give it
/// sections, a palette and a size, and it paints and reports where the buttons are.
struct PopoverRenderer {
    enum Button: Equatable {
        case accounts, refresh, quit
        case back, addAccount, openKeyPage, submit
        case remove(Foundation.UUID)
        case choose(ProviderKind)
    }

    struct Hit {
        var rect: RECT
        var button: Button
    }

    var sections: [DashboardSection]
    var palette: PopoverPalette
    var dpi: Int
    /// The footer's status text ("Updated 2m ago", "Refreshing…").
    var status: String
    var screen: PopoverScreen = .dashboard
    var accounts: [AccountSummary] = []
    /// A short message on the add-account form ("Paste your API key first.").
    var note: String?

    // Layout, in 96-dpi pixels.
    static let width = 340
    let padding = 14
    let headerHeight = 44
    let noticeHeight = 18
    let rowHeight = 36
    let sectionPadding = 10
    let footerHeight = 40
    let emptyHeight = 92

    func s(_ value: Int) -> Int32 { Win32.scale(value, dpi) }

    /// The height the sections need, without the footer.
    func contentHeight() -> Int32 {
        if screen != .dashboard { return screenHeight() }
        guard !sections.isEmpty else { return s(emptyHeight) }
        let total = sections.reduce(0) { sum, section in
            sum + sectionPadding * 2 + headerHeight + (section.notice == nil ? 0 : noticeHeight) + section.rows.count * rowHeight
        }
        return s(total)
    }

    var footerPixels: Int32 { screen == .dashboard ? s(footerHeight) : 0 }

    /// Paints everything for a view `size` pixels wide and tall, scrolled by `scroll`, and returns the
    /// footer buttons' rectangles.
    func draw(on hdc: HDC, size: SIZE, scroll: Int32) -> [Hit] {
        var area = RECT(left: 0, top: 0, right: size.cx, bottom: size.cy)
        fill(hdc, &area, palette.background)
        SetBkMode(hdc, TRANSPARENT)
        let fonts = Fonts(dpi: dpi)
        defer { fonts.release() }
        if screen != .dashboard { return drawScreen(on: hdc, fonts: fonts, size: size) }

        let contentBottom = size.cy - footerPixels
        var clip = RECT(left: 0, top: 0, right: size.cx, bottom: contentBottom)
        let saved = SaveDC(hdc)
        IntersectClipRect(hdc, clip.left, clip.top, clip.right, clip.bottom)
        var y = -scroll
        if sections.isEmpty {
            drawEmpty(hdc, fonts, width: size.cx, y: y)
        } else {
            for (index, section) in sections.enumerated() {
                y = draw(section, hdc, fonts, width: size.cx, y: y, divider: index > 0)
            }
        }
        RestoreDC(hdc, saved)
        clip = RECT()
        return drawFooter(hdc, fonts, size: size)
    }

    // MARK: - Sections

    private func draw(_ section: DashboardSection, _ hdc: HDC, _ fonts: Fonts, width: Int32, y start: Int32, divider: Bool) -> Int32 {
        var y = start
        let pad = s(padding)
        if divider {
            var line = RECT(left: pad, top: y, right: width - pad, bottom: y + 1)
            fill(hdc, &line, palette.divider)
        }
        y += s(sectionPadding)

        // Provider (and plan) on the first line, the account's name under it.
        let inner = width - pad * 2
        var plan = RECT(left: pad, top: y, right: width - pad, bottom: y + s(22))
        if let planText = section.plan, !planText.isEmpty {
            text(hdc, fonts.small, palette.secondaryText, planText, &plan, DT_RIGHT)
        }
        var title = RECT(left: pad, top: y, right: pad + inner - (section.plan == nil ? 0 : s(110)), bottom: y + s(22))
        text(hdc, fonts.title, palette.text, section.provider, &title, DT_LEFT)
        y += s(22)
        var account = RECT(left: pad, top: y, right: width - pad, bottom: y + s(18))
        let accountLine = section.outdated ? "\(section.account)  ·  Outdated" : section.account
        text(hdc, fonts.small, palette.secondaryText, accountLine, &account, DT_LEFT)
        y += s(headerHeight - 22)
        if let notice = section.notice {
            var rect = RECT(left: pad, top: y, right: width - pad, bottom: y + s(noticeHeight))
            text(hdc, fonts.small, palette.notice, notice, &rect, DT_LEFT)
            y += s(noticeHeight)
        }

        for row in section.rows { y = draw(row, hdc, fonts, width: width, y: y) }
        return y + s(sectionPadding)
    }

    private func draw(_ row: DashboardRowModel, _ hdc: HDC, _ fonts: Fonts, width: Int32, y: Int32) -> Int32 {
        let pad = s(padding)
        let lineHeight = s(18)
        switch row.mark {
        case .value(let value):
            var label = RECT(left: pad, top: y, right: width / 2, bottom: y + lineHeight)
            text(hdc, fonts.body, palette.text, row.label, &label, DT_LEFT)
            var right = RECT(left: width / 2, top: y, right: width - pad, bottom: y + lineHeight)
            text(hdc, fonts.bodyBold, palette.text, value, &right, DT_RIGHT)
        case .bar(let fraction, let severity, let value, let reset, let flame):
            let tint = palette.color(for: severity)
            var label = RECT(left: pad, top: y, right: width / 2, bottom: y + lineHeight)
            text(hdc, fonts.body, palette.text, row.label, &label, DT_LEFT)

            var right = width - pad
            if let reset {
                let size = measure(hdc, fonts.small, reset)
                var rect = RECT(left: right - size, top: y, right: right, bottom: y + lineHeight)
                text(hdc, fonts.small, palette.secondaryText, reset, &rect, DT_RIGHT)
                right -= size + s(10)
            }
            let shown = flame ? "\u{25B2} \(value)" : value
            let valueWidth = measure(hdc, fonts.bodyBold, shown)
            var valueRect = RECT(left: right - valueWidth, top: y, right: right, bottom: y + lineHeight)
            text(hdc, fonts.bodyBold, severity == .normal ? palette.text : tint, shown, &valueRect, DT_RIGHT)

            // The bar: a rounded track with the share in the state's colour.
            let barTop = y + lineHeight + s(3)
            let barHeight = s(6)
            let trackWidth = width - pad * 2
            roundedBar(hdc, left: pad, top: barTop, width: trackWidth, height: barHeight, color: palette.track)
            let filled = Int32((Double(trackWidth) * min(max(fraction, 0), 1)).rounded())
            if filled > 0 {
                roundedBar(hdc, left: pad, top: barTop, width: max(filled, barHeight), height: barHeight, color: tint)
            }
        }
        return y + s(rowHeight)
    }

    private func drawEmpty(_ hdc: HDC, _ fonts: Fonts, width: Int32, y: Int32) {
        let pad = s(padding)
        var title = RECT(left: pad, top: y + s(22), right: width - pad, bottom: y + s(44))
        text(hdc, fonts.title, palette.text, "No Accounts Yet", &title, DT_CENTER)
        var hint = RECT(left: pad, top: y + s(46), right: width - pad, bottom: y + s(80))
        text(hdc, fonts.small, palette.secondaryText, "Add one from Accounts to see its limits here.", &hint, DT_CENTER | DT_WORDBREAK)
    }

    // MARK: - Footer

    private func drawFooter(_ hdc: HDC, _ fonts: Fonts, size: SIZE) -> [Hit] {
        let pad = s(padding)
        let top = size.cy - footerPixels
        var line = RECT(left: 0, top: top, right: size.cx, bottom: top + 1)
        fill(hdc, &line, palette.divider)

        var hits: [Hit] = []
        var quit = RECT(left: size.cx - pad - s(36), top: top, right: size.cx - pad, bottom: size.cy)
        text(hdc, fonts.body, palette.normal, "Quit", &quit, DT_RIGHT)
        hits.append(Hit(rect: quit, button: .quit))
        var refresh = RECT(left: quit.left - s(66), top: top, right: quit.left - s(14), bottom: size.cy)
        text(hdc, fonts.body, palette.normal, "Refresh", &refresh, DT_RIGHT)
        hits.append(Hit(rect: refresh, button: .refresh))
        var accounts = RECT(left: refresh.left - s(76), top: top, right: refresh.left - s(14), bottom: size.cy)
        text(hdc, fonts.body, palette.normal, "Accounts", &accounts, DT_RIGHT)
        hits.append(Hit(rect: accounts, button: .accounts))
        var status = RECT(left: pad, top: top, right: accounts.left - s(8), bottom: size.cy)
        text(hdc, fonts.small, palette.secondaryText, self.status, &status, DT_LEFT)
        return hits
    }

    // MARK: - Primitives

    func fill(_ hdc: HDC, _ rect: inout RECT, _ color: COLORREF) {
        let brush = CreateSolidBrush(color)
        FillRect(hdc, &rect, brush)
        DeleteObject(brush)
    }

    func roundedBar(_ hdc: HDC, left: Int32, top: Int32, width: Int32, height: Int32, color: COLORREF) {
        let brush = CreateSolidBrush(color)
        let oldBrush = SelectObject(hdc, brush)
        let oldPen = SelectObject(hdc, GetStockObject(NULL_PEN))
        RoundRect(hdc, left, top, left + width + 1, top + height + 1, height, height)
        SelectObject(hdc, oldPen)
        SelectObject(hdc, oldBrush)
        DeleteObject(brush)
    }

    func text(_ hdc: HDC, _ font: HFONT?, _ color: COLORREF, _ string: String, _ rect: inout RECT, _ align: Int32) {
        let old = SelectObject(hdc, font)
        SetTextColor(hdc, color)
        var units = Win32.wide(string)
        let flags = UINT(align | DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX)
        DrawTextW(hdc, &units, -1, &rect, align & DT_WORDBREAK != 0 ? UINT(align | DT_NOPREFIX) : flags)
        SelectObject(hdc, old)
    }

    func measure(_ hdc: HDC, _ font: HFONT?, _ string: String) -> Int32 {
        let old = SelectObject(hdc, font)
        defer { SelectObject(hdc, old) }
        var units = Win32.wide(string)
        var size = SIZE()
        GetTextExtentPoint32W(hdc, &units, Int32(units.count - 1), &size)
        return size.cx
    }

    // MARK: - Fonts

    struct Fonts {
        let title: HFONT?
        let body: HFONT?
        let bodyBold: HFONT?
        let small: HFONT?

        init(dpi: Int) {
            func make(_ pixels: Int, _ weight: Int32) -> HFONT? {
                CreateFontW(
                    -Win32.scale(pixels, dpi), 0, 0, 0, weight, 0, 0, 0,
                    DWORD(DEFAULT_CHARSET), DWORD(OUT_DEFAULT_PRECIS), DWORD(CLIP_DEFAULT_PRECIS),
                    DWORD(CLEARTYPE_QUALITY), DWORD(DEFAULT_PITCH | FF_DONTCARE), Win32.wide("Segoe UI")
                )
            }
            title = make(15, Int32(FW_SEMIBOLD))
            body = make(13, Int32(FW_NORMAL))
            bodyBold = make(13, Int32(FW_SEMIBOLD))
            small = make(12, Int32(FW_NORMAL))
        }

        func release() {
            [title, body, bodyBold, small].forEach { if let font = $0 { DeleteObject(font) } }
        }
    }
}
#endif
