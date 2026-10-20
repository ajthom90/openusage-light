import AppKit
import SwiftUI

struct AccountsSettingsSection: View {
    let store: AccountStore
    let onChange: () -> Void

    @State private var isAdding = false
    @State private var editingAccount: Account?
    @State private var removingAccount: Account?
    @State private var editedLabel = ""

    var body: some View {
        section {
            if store.accounts.isEmpty {
                Text("No Accounts")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.accounts) { account in
                    accountRow(account)
                    if account.id != store.accounts.last?.id { Divider().padding(.leading, 48) }
                }
            }
            Button {
                isAdding = true
            } label: {
                Label("Add Account", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $isAdding) {
            AddAccountSheet(store: store, onAdded: onChange)
        }
        .alert("Rename Account", isPresented: Binding(
            get: { editingAccount != nil },
            set: { if !$0 { editingAccount = nil } }
        )) {
            TextField("Account Name", text: $editedLabel)
            Button("Cancel", role: .cancel) { editingAccount = nil }
            Button("Save") {
                if let editingAccount {
                    store.rename(editingAccount.id, to: editedLabel.trimmingCharacters(in: .whitespacesAndNewlines))
                    onChange()
                }
                editingAccount = nil
            }
        }
        .confirmationDialog(
            "Remove \(removingAccount?.label ?? "Account")?",
            isPresented: Binding(
                get: { removingAccount != nil },
                set: { if !$0 { removingAccount = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Account", role: .destructive) {
                if let removingAccount {
                    store.remove(removingAccount.id)
                    onChange()
                }
                removingAccount = nil
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 10) {
            ProviderIcon(source: account.kind.iconSource)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.kind.displayName)
                    .font(.system(size: 12, weight: .medium))
                Text(account.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Rename…") {
                    editedLabel = account.label
                    editingAccount = account
                }
                Button("Remove Account", role: .destructive) { removingAccount = account }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func section<Content: View>(@ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Accounts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            VStack(spacing: 0, content: rows)
                .cardSurface()
        }
    }
}

private struct AddAccountSheet: View {
    let store: AccountStore
    let onAdded: () -> Void

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
                .buttonStyle(.plain)
                .padding(.vertical, 5)
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
                    .buttonStyle(.borderedProminent)
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
                        .buttonStyle(.borderedProminent)
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
                Text("Waiting for browser sign-in…")
                    .foregroundStyle(.secondary)
                Button("Open Sign-In Page") { openURL(url) }
                    .buttonStyle(.borderedProminent)
            }
        case .deviceCode(let userCode, let url):
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter this code in your browser:")
                    .foregroundStyle(.secondary)
                HStack {
                    Text(userCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                    Spacer()
                    Button("Copy") { NSPasteboard.general.setString(userCode, forType: .string) }
                }
                Button("Open Verification Page") { openURL(url) }
                    .buttonStyle(.borderedProminent)
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
                            if case .browser(let url, _) = prompt { openURL(url) }
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
        onAdded()
        dismiss()
    }

    private func cancel() {
        continuation?.finish()
        loginTask?.cancel()
        dismiss()
    }
}
