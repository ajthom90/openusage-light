import Foundation
import Observation

/// The Add Account sheet's state: the provider being chosen, the running sign-in, and its outcome.
/// It owns the sign-in task so a failed attempt can be retried and a cancelled sheet stops the login.
@MainActor
@Observable
final class AddAccountFlow {
    /// The highlighted row in the provider list; the arrow keys move it.
    var selection: ProviderKind?
    var apiKey = ""
    var accountName = ""
    var pastedCode = ""
    /// The provider being signed in to; nil while the user is still choosing one.
    private(set) var provider: ProviderKind?
    /// What the provider's sign-in asked the user to do; nil until it asks.
    private(set) var prompt: LoginPrompt?
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private(set) var isFinished = false

    private let store: AccountStore
    private let login: (ProviderKind) -> any ProviderLogin
    private var task: Task<Void, Never>?
    private var codeInput: AsyncStream<String>.Continuation?

    init(store: AccountStore, login: @escaping (ProviderKind) -> any ProviderLogin = ProviderLoginCatalog.login(for:)) {
        self.store = store
        self.login = login
    }

    var canAddKey: Bool { !apiKey.trimmed.isEmpty && !isWorking }
    var hasPastedCode: Bool { !pastedCode.trimmed.isEmpty }
    var canSubmitCode: Bool { hasPastedCode && codeInput != nil }
    /// A pasted code was handed to the sign-in, which is now exchanging it.
    var isCodeSubmitted: Bool { isWorking && prompt != nil && codeInput == nil }

    /// Goes to the provider's step, starting its browser or device-code sign-in right away.
    func choose(_ kind: ProviderKind) {
        selection = kind
        provider = kind
        if case .oauth = kind.authMethod { signIn() }
    }

    /// Starts the provider's browser or device-code sign-in, or starts it again after a failure.
    func signIn() {
        guard let provider else { return }
        let (input, continuation) = AsyncStream.makeStream(of: String.self)
        codeInput = continuation
        pastedCode = ""
        run(provider, input: input)
    }

    /// Hands a code the user pasted from the browser to the waiting sign-in.
    func submitCode() {
        guard canSubmitCode else { return }
        codeInput?.yield(pastedCode)
        codeInput?.finish()
        codeInput = nil
    }

    func addKey() {
        guard let provider, canAddKey else { return }
        let (input, continuation) = AsyncStream.makeStream(of: String.self)
        continuation.yield(apiKey)
        continuation.finish()
        run(provider, input: input)
    }

    /// Returns from the provider's step to the provider list, stopping its sign-in and keeping that
    /// provider selected.
    func back() {
        cancel()
        provider = nil
        prompt = nil
        errorMessage = nil
        isWorking = false
        apiKey = ""
        accountName = ""
        pastedCode = ""
    }

    func cancel() {
        task?.cancel()
        task = nil
        codeInput?.finish()
        codeInput = nil
    }

    private func run(_ kind: ProviderKind, input: AsyncStream<String>) {
        task?.cancel()
        prompt = nil
        errorMessage = nil
        isWorking = true
        let login = login(kind)
        task = Task {
            do {
                let result = try await login.login(
                    prompt: { prompt in await self.show(prompt) },
                    pastedCode: input
                )
                guard !Task.isCancelled else { return }
                save(result, for: kind)
            } catch {
                guard !Task.isCancelled else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func show(_ prompt: LoginPrompt) {
        guard !Task.isCancelled else { return }
        self.prompt = prompt
    }

    private func save(_ result: (label: String, credential: AccountCredential), for kind: ProviderKind) {
        let name = accountName.trimmed
        let account = store.add(kind: kind, label: name.isEmpty ? result.label : name, credential: result.credential)
        guard store.accounts.contains(where: { $0.id == account.id }) else {
            return fail(store.lastError ?? "The account could not be saved.")
        }
        codeInput?.finish()
        codeInput = nil
        isWorking = false
        isFinished = true
    }

    private func fail(_ message: String) {
        codeInput?.finish()
        codeInput = nil
        prompt = nil
        isWorking = false
        errorMessage = message
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
