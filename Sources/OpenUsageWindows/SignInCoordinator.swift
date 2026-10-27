#if os(Windows)
import Foundation
import OpenUsageCore

/// Runs one browser-approval sign-in at a time with the sign-in code shared with the Mac app, and keeps
/// the popover's sign-in page up to date as the code arrives, succeeds, or fails.
@MainActor
final class SignInCoordinator {
    private var task: Task<Void, Never>?

    func start(_ kind: ProviderKind, model: DashboardModel, popover: PopoverWindow, refreshAfter: Bool) {
        task?.cancel()
        guard let login = SharedProviderLogins.login(for: kind) else { return }
        task = Task { @MainActor in
            do {
                let result = try await login.login(
                    prompt: { prompt in popover.setSignInPrompt(kind: kind, prompt: prompt) },
                    pastedCode: AsyncStream { $0.finish() }
                )
                guard !Task.isCancelled else { return }
                model.accounts.add(kind: kind, label: result.label, credential: result.credential)
                model.reload()
                popover.finishSignIn()
                if refreshAfter { await model.refresh(force: true) }
            } catch is CancellationError {
                // The user backed out; the page is already gone.
            } catch {
                popover.failSignIn(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
#endif
