import AppKit
import SwiftUI

/// Adds an account: pick a provider, then finish its browser, device-code, or API-key sign-in. Opened
/// from the Accounts list and the empty dashboard.
struct AddAccountSheet: View {
    let store: AccountStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var kind: ProviderKind?
    @State private var promptValue: LoginPrompt?
    @State private var code = ""
    @State private var label = ""
    @State private var errorMessage: String?
    @State private var isSigningIn = false
    @State private var loginTask: Task<Void, Never>?
    @State private var continuation: AsyncStream<String>.Continuation?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(kind == nil ? "Add Account" : "Sign In")
                    .font(.headline)
                Spacer()
                Button("Cancel") { cancel() }
                    .glassButtonStyle()
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            if let kind {
                signInContent(for: kind)
            } else {
                providerPicker
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onDisappear { loginTask?.cancel() }
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a provider")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(ProviderKind.allCases, id: \.self) { provider in
                Button {
                    kind = provider
                    if provider.authMethod == .oauth { startOAuth(provider) }
                } label: {
                    HStack(spacing: 10) {
                        ProviderIcon(source: provider.iconSource)
                            .frame(width: 22, height: 22)
                        Text(provider.displayName)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .glassButtonStyle()
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func signInContent(for kind: ProviderKind) -> some View {
        if kind.authMethod == .apiKey {
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter your \(kind.displayName) API key.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("API Key", text: $code)
                    .textFieldStyle(.roundedBorder)
                TextField("Account Name (Optional)", text: $label)
                    .textFieldStyle(.roundedBorder)
                Button("Add Account") { addAPIKey(kind) }
                    .glassButtonStyle(prominent: true)
                    .controlSize(.small)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if isSigningIn {
                    progressContent
                } else {
                    Text("Preparing sign-in…")
                        .foregroundStyle(.secondary)
                }
                if case .browser(_, let acceptsPastedCode) = promptValue, acceptsPastedCode {
                    TextField("Paste Authorization Code", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submitCode() }
                    Button("Continue") { submitCode() }
                        .glassButtonStyle(prominent: true)
                        .controlSize(.small)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var progressContent: some View {
        switch promptValue {
        case .browser(let url, _):
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign in with your browser.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Open in Browser") { openURL(url) }
                        .glassButtonStyle(prominent: true)
                        .controlSize(.small)
                    Button("Copy Link") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(url.absoluteString, forType: .string)
                    }
                    .glassButtonStyle()
                    .controlSize(.small)
                }
            }
        case .deviceCode(let userCode, let url):
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter this code in your browser:")
                    .foregroundStyle(.secondary)
                HStack {
                    Text(userCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                }
                HStack(spacing: 8) {
                    Button("Copy") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(userCode, forType: .string)
                    }
                    .glassButtonStyle()
                    .controlSize(.small)
                    Button("Open Verification Page") { openURL(url) }
                        .glassButtonStyle(prominent: true)
                        .controlSize(.small)
                }
                Text("This window will finish when sign-in completes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case nil:
            ProgressView()
                .controlSize(.small)
        }
    }

    private func startOAuth(_ kind: ProviderKind) {
        var stream: AsyncStream<String>!
        stream = AsyncStream { continuation = $0 }
        isSigningIn = true
        loginTask = Task {
            do {
                let result = try await ProviderLoginCatalog.login(for: kind).login(
                    prompt: { prompt in
                        await MainActor.run {
                            promptValue = prompt
                        }
                    },
                    pastedCode: stream
                )
                await MainActor.run { save(result, for: kind) }
            } catch is CancellationError {
                await MainActor.run { errorMessage = "Sign-in was cancelled." }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSigningIn = false
                }
            }
        }
    }

    private func submitCode() {
        continuation?.yield(code)
        continuation?.finish()
        continuation = nil
    }

    private func addAPIKey(_ kind: ProviderKind) {
        let stream = AsyncStream<String> { continuation in
            continuation.yield(code)
            continuation.finish()
        }
        isSigningIn = true
        loginTask = Task {
            do {
                let result = try await ProviderLoginCatalog.login(for: kind).login(prompt: { _ in }, pastedCode: stream)
                await MainActor.run { save(result, for: kind) }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSigningIn = false
                }
            }
        }
    }

    private func save(_ result: (label: String, credential: AccountCredential), for kind: ProviderKind) {
        let accountLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? result.label
            : label.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = store.add(kind: kind, label: accountLabel, credential: result.credential)
        guard store.accounts.contains(where: { $0.id == account.id }) else {
            errorMessage = store.lastError ?? "The account could not be saved."
            isSigningIn = false
            return
        }
        continuation?.finish()
        dismiss()
    }

    private func cancel() {
        continuation?.finish()
        loginTask?.cancel()
        dismiss()
    }
}
