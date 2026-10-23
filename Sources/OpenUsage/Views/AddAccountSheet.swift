import AppKit
import SwiftUI

/// Adds an account: choose a provider, then finish its browser, device-code, or API-key sign-in.
/// Opened as a sheet on the popover from the Accounts list and the empty dashboard.
struct AddAccountSheet: View {
    @State private var flow: AddAccountFlow
    @Environment(\.dismiss) private var dismiss

    init(store: AccountStore) {
        _flow = State(initialValue: AddAccountFlow(store: store))
    }

    init(flow: AddAccountFlow) {
        _flow = State(initialValue: flow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let provider = flow.provider {
                if case .apiKey(let keyPage) = provider.authMethod {
                    APIKeyStep(flow: flow, provider: provider, keyPage: keyPage, cancel: { flow.back() })
                } else {
                    BrowserSignInStep(flow: flow, provider: provider, cancel: { flow.back() })
                }
            } else {
                ProviderChoiceStep(flow: flow, cancel: { dismiss() })
            }
        }
        .frame(width: 300)
        // The popover panel takes keys without activating the app, but this sheet is an ordinary
        // window: without activation its fields never receive typing.
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
        .onDisappear { flow.cancel() }
        .onChange(of: flow.isFinished) { _, isFinished in
            if isFinished { dismiss() }
        }
    }
}

/// The provider list, like Internet Accounts' Add Account: one click on a provider goes straight to
/// its sign-in. The arrow keys move the selection and Return chooses it.
private struct ProviderChoiceStep: View {
    @Bindable var flow: AddAccountFlow
    let cancel: () -> Void
    @FocusState private var isListFocused: Bool

    var body: some View {
        SheetHeader(provider: nil, title: "Add Account", message: "Choose a provider to sign in to.")
        List(ProviderKind.allCases, id: \.self, selection: $flow.selection) { provider in
            HStack(spacing: 10) {
                ProviderIcon(source: provider.iconSource, inset: 0.06)
                    .frame(width: 20, height: 20)
                Text(provider.displayName)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
            .onTapGesture { flow.choose(provider) }
            .listItemTint(.monochrome)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .background(Theme.cardFill, in: .rect(cornerRadius: 10))
        .frame(height: CGFloat(ProviderKind.allCases.count) * 28 + 20)
        .padding(.horizontal, 20)
        .focused($isListFocused)
        .contextMenu(forSelectionType: ProviderKind.self, menu: { _ in }, primaryAction: { providers in
            if let provider = providers.first { flow.choose(provider) }
        })
        .onAppear { isListFocused = true }
        HStack {
            Spacer()
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }
}

private struct BrowserSignInStep: View {
    @Bindable var flow: AddAccountFlow
    let provider: ProviderKind
    let cancel: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        SheetHeader(provider: provider, title: "Sign In to \(provider.displayName)", message: message)
        Group {
            if let errorMessage = flow.errorMessage {
                ErrorText(errorMessage)
            } else {
                if case .deviceCode(let userCode, _) = flow.prompt {
                    DeviceCodeBox(code: userCode)
                        .padding(.bottom, 12)
                }
                status
            }
        }
        .padding(.horizontal, 20)
        if flow.errorMessage == nil, case .browser(_, acceptsPastedCode: true) = flow.prompt {
            pastedCodeForm
                .padding(.top, 12)
        }
        SheetButtons(cancel: cancel, primary: primaryAction)
    }

    private var message: String {
        switch flow.prompt {
        case .deviceCode: "Open the verification page in your browser and enter this code."
        case .browser, nil: "Continue in your browser. This sheet closes when you’re signed in."
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            if flow.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(statusText)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if case .browser(let url, _) = flow.prompt {
                Button("Copy Link") { copy(url.absoluteString) }
                    .buttonStyle(.link)
            }
        }
        .font(.callout)
    }

    private var statusText: String {
        if flow.prompt == nil { return "Preparing sign-in…" }
        return flow.isCodeSubmitted ? "Signing in…" : "Waiting for your browser…"
    }

    private var pastedCodeForm: some View {
        Form {
            Section {
                TextField("Code", text: $flow.pastedCode, prompt: Text("Paste code"))
                    .onSubmit { flow.submitCode() }
                    .disabled(flow.isCodeSubmitted)
            } footer: {
                Text("Paste the code here if your browser shows one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .inlineGroupedForm()
    }

    private var primaryAction: SheetAction {
        if flow.errorMessage != nil {
            return SheetAction(title: "Try Again") { flow.signIn() }
        }
        if flow.hasPastedCode {
            return SheetAction(title: "Continue", isDisabled: !flow.canSubmitCode) { flow.submitCode() }
        }
        return SheetAction(title: "Open Browser", isDisabled: flow.prompt == nil) { open() }
    }

    private func open() {
        switch flow.prompt {
        case .browser(let url, _): openURL(url)
        case .deviceCode(_, let url): openURL(url)
        case nil: break
        }
    }
}

private struct APIKeyStep: View {
    @Bindable var flow: AddAccountFlow
    let provider: ProviderKind
    let keyPage: URL
    let cancel: () -> Void

    var body: some View {
        SheetHeader(
            provider: provider,
            title: "Add \(provider.displayName)",
            message: "Enter an API key from your \(provider.displayName) account. It’s stored in your Keychain.",
            link: Link("Get Your API Key", destination: keyPage)
        )
        Form {
            Section {
                SecureField("API Key", text: $flow.apiKey, prompt: Text("Required"))
                    .onSubmit { flow.addKey() }
                TextField("Name", text: $flow.accountName, prompt: Text(provider.displayName))
                    .onSubmit { flow.addKey() }
            } footer: {
                if let errorMessage = flow.errorMessage {
                    ErrorText(errorMessage)
                }
            }
        }
        .inlineGroupedForm()
        SheetButtons(cancel: cancel, primary: SheetAction(title: "Add Account", isDisabled: !flow.canAddKey) { flow.addKey() })
    }
}

/// The title block every step opens with, left-aligned like a macOS alert: the provider's mark
/// once one is chosen, a bold title, and one line of guidance.
private struct SheetHeader: View {
    let provider: ProviderKind?
    let title: String
    let message: String
    var link: Link<Text>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let provider {
                ProviderIcon(source: provider.iconSource, inset: 0.04)
                    .frame(width: 32, height: 32)
                    .padding(.bottom, 8)
            }
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let link {
                link
                    .font(.subheadline)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 14)
    }
}

/// The step's default button: Return presses it.
private struct SheetAction {
    let title: String
    var isDisabled = false
    let action: () -> Void
}

/// Cancel and the step's default button, each half the sheet's width. Escape cancels and Return
/// presses the default button. On a provider's step, Cancel goes back to the provider list.
private struct SheetButtons: View {
    let cancel: () -> Void
    let primary: SheetAction

    var body: some View {
        HStack {
            Button(action: cancel) {
                Text("Cancel").frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.cancelAction)
            Button(action: primary.action) {
                Text(primary.title).frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(primary.isDisabled)
        }
        .padding(20)
    }
}

private struct DeviceCodeBox: View {
    let code: String

    var body: some View {
        HStack {
            Text(code)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
            Spacer()
            Button("Copy Code", systemImage: "doc.on.doc") { copy(code) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copy Code")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardFill, in: .rect(cornerRadius: 10))
    }
}

private struct ErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// A grouped form laid out inline in the sheet: sized to its rows instead of scrolling, and
    /// without the extra vertical margin the form adds around itself when it fills a window.
    func inlineGroupedForm() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, -16)
    }
}

@MainActor
private func copy(_ string: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
}
