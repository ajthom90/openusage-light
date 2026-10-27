# iOS and iPadOS app with widgets: design notes

Status: **idea, parked, not approved.** Nothing is built. This records what is known so the work can start from here later.

## Intent

An iPhone and iPad app, with Home Screen and Lock Screen widgets, showing the usage limits of the accounts added on the owner's other devices, so the numbers are visible away from the Mac.

## Constraints from the project (AGENTS.md)

- Provider-reported limits and dollar values only; no estimates, no log scanning.
- Sign-in happens inside the app. Never read other tools' credentials, files, or Keychain items.
- Credentials live in the app's own storage.
- The user's saved provider and account order is kept everywhere.

## The question that started this

Could the phone share logins with the Mac over iCloud Keychain? **Technically yes, but it is not the design to start with** (see "Recommended shape").

## What is possible

- **iCloud Keychain sync.** A keychain item saved with the synchronizable attribute appears on the owner's other devices signed into the same iCloud account with Keychain on. A keychain access group lets the app and its widget extension read the same item.
- **Portable core.** `OpenUsageCore` imports only Foundation, so it should build for iOS and iPadOS with a platform entry added to `Package.swift`. The provider clients, mappers, formatters, and the `DashboardRowModel` row model would be reused. New code is SwiftUI views and a WidgetKit extension.
- **API-key accounts** (Ollama, OpenCode, OpenRouter, Z.ai) would work on the phone with no extra sign-in design.

## What needs care

1. **The Mac does not use a syncing keychain today.** `KeychainCredentialVault` uses the older file-based keychain, which cannot sync. Syncing needs the data-protection keychain, which needs `keychain-access-groups` entitlements and a provisioning profile tied to the owner's Apple team. The dev builds are signed with an Apple Development identity and `get-task-allow` only. Moving accounts to the new keychain is a migration with its own tests.
2. **Refresh-token rotation.** Claude and Codex rotate their refresh tokens when they are used (this is how the Mac runtimes treat them: the refreshed set is saved back to the vault). If a Mac and a phone both refresh one account, the second can find its token already invalid, and iCloud sync latency makes that race likely. Whatever is built must have exactly one device that refreshes each account. *Not tested against the real providers.*
3. **OAuth sign-in on iOS.** The providers' sign-ins on the Mac redirect to a localhost address handled by a loopback listener. A phone cannot easily offer that, and the registered redirect addresses are the providers' choice. The Mac app already has a paste-the-code fallback, which is the likely route. *Which providers accept it is unverified.*
4. **Widgets have a small refresh budget.** iOS decides when a widget refreshes. A widget mostly shows data the app or system fetched earlier, so it cannot be the thing that refreshes tokens.
5. **Two separate Apple programs to confirm:** an App Store (or TestFlight) distribution path and an App Group for the widget are needed, and both need the owner's paid developer account.

## Recommended shape

**The Mac stays the only device that signs in and refreshes. The phone shows what the Mac found.**

- The Mac writes each account's latest snapshot (the same `ProviderSnapshot` it caches today) to iCloud, using a small CloudKit record or iCloud key-value storage.
- The iOS app and its widgets read those snapshots and draw them with the shared row model.
- The phone holds **no provider tokens**, so there is no rotation race, nothing sensitive to leak from a lost phone, and the project's credential rules are kept as they are.
- Cost: the phone updates only while a Mac is awake and online. The widget can show the snapshot's age, as the Mac app's "Outdated" hint does.

**Optional later:** API-key accounts could also sync their keys over iCloud Keychain so the phone can refresh them itself, since a static key has no rotation problem.

## Open questions for the owner

- Is "updates only while a Mac is awake" acceptable, or does the phone need to refresh on its own?
- Is a paid Apple developer account available for entitlements, App Groups, and distribution?
- Phone only, or iPad too (the layout would differ)?
- Which widget sizes matter (Lock Screen, small, medium)?

## Not decided here

Names, icons, pricing, release timing, and how an iOS app would be tested without a device.
