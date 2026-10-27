#if os(Windows)
import Foundation
import OpenUsageCore
import WinSDK

/// Which page the popover shows. The dashboard is the default; the rest are the add-account flow.
enum PopoverScreen: Equatable {
    case dashboard
    case accounts
    case picker
    case entry(ProviderKind)
    case signIn(ProviderKind)
}

/// A browser sign-in in progress: the code to enter and the page to open, or why it stopped.
struct SignInState: Equatable, Sendable {
    var kind: ProviderKind
    var userCode: String?
    var url: URL?
    var errorMessage: String?
    var acceptsPastedCode = false
    /// A pasted code has been sent and the sign-in is finishing.
    var submitted = false
    var finished = false
}

/// How a provider signs in on this platform.
enum SignInMethod: Equatable {
    case apiKey
    /// A code (or link) approved in a browser, using the sign-in code shared with the Mac app.
    case browserApproval
    case unavailable

    init(_ kind: ProviderKind) {
        if case .apiKey = kind.authMethod { self = .apiKey }
        else if SharedProviderLogins.login(for: kind, callbackServer: WinsockCallbackServer.factory) != nil { self = .browserApproval }
        else { self = .unavailable }
    }
}

/// An account as the accounts page lists it, in the dashboard's order.
struct AccountSummary: Equatable, Sendable {
    let id: Foundation.UUID
    let kind: ProviderKind
    let label: String
}

extension PopoverRenderer {
    private var titleHeight: Int { 46 }
    private var accountRowHeight: Int { 48 }
    private var pickerRowHeight: Int { 42 }

    /// Providers that sign in with a pasted key come first, then the browser approvals, then the rest.
    static var pickerKinds: [ProviderKind] {
        ProviderKind.allCases.filter { SignInMethod($0) == .apiKey }
            + ProviderKind.allCases.filter { SignInMethod($0) == .browserApproval }
            + ProviderKind.allCases.filter { SignInMethod($0) == .unavailable }
    }

    func screenHeight() -> Int32 {
        switch screen {
        case .dashboard: 0
        case .accounts: s(titleHeight + max(accounts.count, 1) * accountRowHeight + 64)
        case .picker: s(titleHeight + Self.pickerKinds.count * pickerRowHeight + 24)
        case .entry: s(titleHeight + 172)
        case .signIn: s(signInLayout().height)
        }
    }

    /// The key text box's rectangle in client pixels (the real text box is placed over it).
    func entryFieldRect(width: Int32) -> RECT {
        let pad = s(padding)
        let top = s(titleHeight + 40)
        return RECT(left: pad, top: top, right: width - pad, bottom: top + s(32))
    }

    func drawScreen(on hdc: HDC, fonts: Fonts, size: SIZE) -> [Hit] {
        var hits: [Hit] = []
        switch screen {
        case .dashboard: break
        case .accounts: drawAccounts(hdc, fonts, size, &hits)
        case .picker: drawPicker(hdc, fonts, size, &hits)
        case .entry(let kind): drawEntry(kind, hdc, fonts, size, &hits)
        case .signIn(let kind): drawSignIn(kind, hdc, fonts, size, &hits)
        }
        return hits
    }

    // MARK: - Pages

    private func drawAccounts(_ hdc: HDC, _ fonts: Fonts, _ size: SIZE, _ hits: inout [Hit]) {
        let pad = s(padding)
        header("Accounts", button: "Done", action: .back, hdc, fonts, size, &hits)
        var y = s(titleHeight)
        if accounts.isEmpty {
            var rect = RECT(left: pad, top: y, right: size.cx - pad, bottom: y + s(accountRowHeight))
            text(hdc, fonts.small, palette.secondaryText, "No accounts yet.", &rect, DT_LEFT)
            y += s(accountRowHeight)
        }
        for account in accounts {
            var rule = RECT(left: pad, top: y, right: size.cx - pad, bottom: y + 1)
            fill(hdc, &rule, palette.divider)
            var name = RECT(left: pad, top: y + s(6), right: size.cx - pad - s(80), bottom: y + s(26))
            text(hdc, fonts.body, palette.text, account.kind.displayName, &name, DT_LEFT)
            var label = RECT(left: pad, top: y + s(26), right: size.cx - pad - s(80), bottom: y + s(44))
            text(hdc, fonts.small, palette.secondaryText, account.label, &label, DT_LEFT)
            var remove = RECT(left: size.cx - pad - s(70), top: y, right: size.cx - pad, bottom: y + s(accountRowHeight))
            text(hdc, fonts.body, palette.critical, "Remove", &remove, DT_RIGHT)
            hits.append(Hit(rect: remove, button: .remove(account.id)))
            y += s(accountRowHeight)
        }
        var add = RECT(left: pad, top: y + s(8), right: size.cx / 2, bottom: y + s(40))
        text(hdc, fonts.bodyBold, palette.normal, "Add Account", &add, DT_LEFT)
        hits.append(Hit(rect: add, button: .addAccount))
    }

    private func drawPicker(_ hdc: HDC, _ fonts: Fonts, _ size: SIZE, _ hits: inout [Hit]) {
        let pad = s(padding)
        header("Add Account", button: "Cancel", action: .back, hdc, fonts, size, &hits)
        var y = s(titleHeight)
        for kind in Self.pickerKinds {
            var rule = RECT(left: pad, top: y, right: size.cx - pad, bottom: y + 1)
            fill(hdc, &rule, palette.divider)
            let method = SignInMethod(kind)
            let available = method != .unavailable
            var name = RECT(left: pad, top: y, right: size.cx - pad - s(110), bottom: y + s(pickerRowHeight))
            text(hdc, fonts.body, available ? palette.text : palette.secondaryText, kind.displayName, &name, DT_LEFT)
            var detail = RECT(left: size.cx - pad - s(110), top: y, right: size.cx - pad, bottom: y + s(pickerRowHeight))
            text(hdc, fonts.small, palette.secondaryText, method == .apiKey ? "API Key  \u{203A}" : (method == .browserApproval ? "Sign In  \u{203A}" : "Coming Soon"), &detail, DT_RIGHT)
            if available {
                hits.append(Hit(rect: RECT(left: 0, top: y, right: size.cx, bottom: y + s(pickerRowHeight)), button: .choose(kind)))
            }
            y += s(pickerRowHeight)
        }
    }

    private func drawEntry(_ kind: ProviderKind, _ hdc: HDC, _ fonts: Fonts, _ size: SIZE, _ hits: inout [Hit]) {
        let pad = s(padding)
        header(kind.displayName, button: "Cancel", action: .back, hdc, fonts, size, &hits)
        var label = RECT(left: pad, top: s(titleHeight + 12), right: size.cx - pad, bottom: s(titleHeight + 36))
        text(hdc, fonts.small, palette.secondaryText, "API Key", &label, DT_LEFT)

        // The box the real text control sits on, so an off-screen snapshot shows where it goes.
        var field = entryFieldRect(width: size.cx)
        fill(hdc, &field, palette.track)

        let below = field.bottom + s(10)
        if case .apiKey = kind.authMethod {
            var link = RECT(left: pad, top: below, right: size.cx / 2, bottom: below + s(24))
            text(hdc, fonts.small, palette.normal, "Get a Key", &link, DT_LEFT)
            hits.append(Hit(rect: link, button: .openKeyPage))
        }
        var add = RECT(left: size.cx / 2, top: below, right: size.cx - pad, bottom: below + s(24))
        text(hdc, fonts.bodyBold, palette.normal, "Add", &add, DT_RIGHT)
        hits.append(Hit(rect: add, button: .submit))
        if let note {
            var message = RECT(left: pad, top: below + s(32), right: size.cx - pad, bottom: below + s(54))
            text(hdc, fonts.small, palette.notice, note, &message, DT_LEFT)
        } else {
            var hint = RECT(left: pad, top: below + s(32), right: size.cx - pad, bottom: below + s(70))
            text(hdc, fonts.small, palette.secondaryText, "Kept encrypted on this PC.", &hint, DT_LEFT)
        }
    }

    /// Where each part of the sign-in page sits (96-dpi units from the top), which depends on whether the
    /// provider shows a code and accepts a pasted one. Shared by drawing and by placing the text box.
    struct SignInLayout {
        var intro = 0, codeBox: Int?, status = 0, buttons = 0, pasteLabel: Int?, field: Int?, height = 0
    }

    func signInLayout() -> SignInLayout {
        var layout = SignInLayout()
        var y = titleHeight + 6
        layout.intro = y
        y += 48
        if signIn?.userCode != nil {
            layout.codeBox = y
            y += 64
        }
        layout.status = y
        y += 28
        layout.buttons = y
        y += 30
        if signIn?.acceptsPastedCode == true {
            layout.pasteLabel = y + 6
            layout.field = y + 30
            y += 30 + 32 + 12 + 30
        }
        layout.height = y + 12
        return layout
    }

    /// The paste box's rectangle in client pixels (the real text box is placed over it).
    func pasteFieldRect(width: Int32) -> RECT? {
        guard let top = signInLayout().field else { return nil }
        let pad = s(padding)
        return RECT(left: pad, top: s(top), right: width - pad, bottom: s(top + 32))
    }

    private func drawSignIn(_ kind: ProviderKind, _ hdc: HDC, _ fonts: Fonts, _ size: SIZE, _ hits: inout [Hit]) {
        let pad = s(padding)
        header("Sign In to \(kind.displayName)", button: "Cancel", action: .back, hdc, fonts, size, &hits)
        let state = signIn
        let layout = signInLayout()
        if let message = state?.errorMessage {
            var rect = RECT(left: pad, top: s(titleHeight + 6), right: size.cx - pad, bottom: s(titleHeight + 76))
            text(hdc, fonts.small, palette.notice, message, &rect, DT_LEFT | DT_WORDBREAK)
            var retry = RECT(left: pad, top: s(titleHeight + 96), right: size.cx - pad, bottom: s(titleHeight + 122))
            text(hdc, fonts.bodyBold, palette.normal, SignInCopy.tryAgain, &retry, DT_LEFT)
            hits.append(Hit(rect: retry, button: .retrySignIn))
            return
        }
        let ready = state?.url != nil
        let instruction = state?.userCode == nil
            ? "Continue in your browser. This closes when you\u{2019}re signed in."
            : SignInCopy.deviceCodeInstruction
        var intro = RECT(left: pad, top: s(layout.intro), right: size.cx - pad, bottom: s(layout.intro + 40))
        text(hdc, fonts.small, palette.secondaryText, ready ? instruction : SignInCopy.preparing, &intro, DT_LEFT | DT_WORDBREAK)
        if let boxTop = layout.codeBox, let code = state?.userCode {
            var box = RECT(left: pad, top: s(boxTop), right: size.cx - pad, bottom: s(boxTop + 52))
            fill(hdc, &box, palette.track)
            text(hdc, fonts.code, palette.text, code, &box, DT_CENTER)
        }
        var status = RECT(left: pad, top: s(layout.status), right: size.cx - pad, bottom: s(layout.status + 24))
        let statusText = !ready ? SignInCopy.preparing : (state?.submitted == true ? SignInCopy.signingIn : SignInCopy.waitingForBrowser)
        text(hdc, fonts.small, palette.secondaryText, statusText, &status, DT_LEFT)
        if ready {
            var open = RECT(left: pad, top: s(layout.buttons), right: size.cx / 2, bottom: s(layout.buttons + 26))
            text(hdc, fonts.bodyBold, palette.normal, SignInCopy.openBrowser, &open, DT_LEFT)
            hits.append(Hit(rect: open, button: .openSignInPage))
            var copy = RECT(left: size.cx / 2, top: s(layout.buttons), right: size.cx - pad, bottom: s(layout.buttons + 26))
            text(hdc, fonts.body, palette.normal, "Copy Link", &copy, DT_RIGHT)
            hits.append(Hit(rect: copy, button: .copySignInLink))
        }
        if let labelTop = layout.pasteLabel, let fieldTop = layout.field {
            var label = RECT(left: pad, top: s(labelTop), right: size.cx - pad, bottom: s(labelTop + 22))
            text(hdc, fonts.small, palette.secondaryText, "If your browser shows a code, paste it here:", &label, DT_LEFT)
            var field = RECT(left: pad, top: s(fieldTop), right: size.cx - pad, bottom: s(fieldTop + 32))
            fill(hdc, &field, palette.track)
            var next = RECT(left: size.cx / 2, top: s(fieldTop + 40), right: size.cx - pad, bottom: s(fieldTop + 66))
            text(hdc, fonts.bodyBold, palette.normal, "Continue", &next, DT_RIGHT)
            hits.append(Hit(rect: next, button: .submitCode))
        }
    }

    // MARK: - Pieces

    /// A page title on the left and one action on the right.
    private func header(_ title: String, button: String, action: Button, _ hdc: HDC, _ fonts: Fonts, _ size: SIZE, _ hits: inout [Hit]) {
        let pad = s(padding)
        var heading = RECT(left: pad, top: s(10), right: size.cx - pad - s(80), bottom: s(titleHeight - 6))
        text(hdc, fonts.title, palette.text, title, &heading, DT_LEFT)
        var action_ = RECT(left: size.cx - pad - s(80), top: s(10), right: size.cx - pad, bottom: s(titleHeight - 6))
        text(hdc, fonts.body, palette.normal, button, &action_, DT_RIGHT)
        hits.append(Hit(rect: action_, button: action))
    }
}
#endif
