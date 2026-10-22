import Foundation
import Observation

/// The one account name being edited in place, on a dashboard card header or as the Accounts detail
/// title. Return or a click elsewhere commits the edit; Esc cancels it. Committing saves the trimmed
/// draft, and an empty or unchanged draft keeps the current name.
@MainActor
@Observable
final class AccountRenameStore {
    /// One open edit. Each `begin` opens a new one, so a field that outlives its edit (still losing focus
    /// while the next one starts) can only close its own.
    struct Edit: Equatable {
        let providerID: String
        fileprivate let serial: Int
    }

    /// The open edit, or nil while no name is being edited.
    private(set) var edit: Edit?
    /// The text field's contents while an edit is open.
    var draft = ""
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private let accounts: AccountStore

    init(accounts: AccountStore) {
        self.accounts = accounts
    }

    func isRenaming(_ providerID: String) -> Bool {
        edit?.providerID == providerID
    }

    /// Opens an edit of the account behind a dashboard card (`Provider.id`), seeded with its name. Any
    /// edit still open is committed first.
    func begin(_ providerID: String) {
        guard let account = accounts.account(cardID: providerID) else { return }
        commit()
        serial += 1
        edit = Edit(providerID: providerID, serial: serial)
        draft = account.label
    }

    /// Closes the open edit, or only `edit` when given and still open, and saves its draft as the
    /// account's name unless it's empty or unchanged.
    func commit(_ edit: Edit? = nil) {
        guard let open = close(edit) else { return }
        let label = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty,
              let account = accounts.account(cardID: open.providerID),
              account.label != label else { return }
        accounts.rename(account.id, to: label)
    }

    /// Closes the open edit, or only `edit` when given and still open, without saving.
    func cancel(_ edit: Edit? = nil) {
        close(edit)
    }

    @discardableResult
    private func close(_ edit: Edit?) -> Edit? {
        guard let open = self.edit, edit == nil || edit == open else { return nil }
        self.edit = nil
        return open
    }
}
