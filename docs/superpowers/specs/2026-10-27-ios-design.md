# iOS and iPadOS app with widgets: design notes

Status: **approved and started (2026-10-28), on the fork's `ios` branch.** The first slice is built; see "Decisions" and "Built so far" at the end.

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

## Owner's answers (2026-10-27)

- **"Updates only while a Mac is awake": acceptable.** The recommended shape stands as written.
- **Paid Apple developer account: available.** Entitlements, App Groups, and TestFlight/App Store distribution are open to us.
- **Devices: iPhone, iPad, and iPhone Duo are all required.** iPhone Duo is a new foldable iPhone ([Apple's page](https://developer.apple.com/iphone-duo/)). That page, as read on 2026-10-27, gives no specifications. What it does say: Xcode 27.1 provides the SDKs to build and test for it; apps should "dynamically resize and adjust" their layouts and "explore resizability for all screen sizes"; its video titles cover adaptive layouts, multiple displays and scenes, and the camera; and the App Store has a "Made for iPhone Duo" badge. Screen sizes, size classes, and multitasking rules are on its Human Interface Guidelines and "Preparing your app for iPhone Duo" pages, **which I have not read**. Read them before any layout work.
- **Widgets: varying sizes wanted.** Plan on the small, medium, and large Home Screen families and the Lock Screen families, each drawing from the shared row model. Exact sizes per device to be settled at design time.

## Still open

- iPhone Duo's actual display and scene behavior (the HIG and "Preparing your app" pages).
- Whether API-key accounts should also sync their keys so the phone can refresh them itself, or the phone should stay display-only for every account.

## Not decided here

Names, icons, pricing, release timing, and how an iOS app would be tested without a device.

## Decisions (2026-10-28)

The owner approved the recommended shape and these choices:

- **The Mac is the only writer; the phone holds no tokens.** The Mac publishes the existing `openusage.limits.v1` document (the same JSON the `openusage` command prints) as one CloudKit record in the user's private database, in an **encrypted field**. It already carries only provider-reported numbers, the account name, and the saved order, so it is the right payload and needs no new format. `LimitsEnvelope.decode` reads it back.
- **Mac sync is opt-in** and stays off until an iCloud container is configured at build time, so the Mac app behaves as before for everyone else.
- **Identifiers:** bundle IDs use the owner's own reverse-DNS prefix (the iOS app is `<prefix>.ios`) and the container is `iCloud.<prefix>`. They live in `iOS/Config/Local.xcconfig`, which git ignores. `iOS/Config/Shared.xcconfig` holds blank placeholders, and `script/hooks/pre-commit` (enable with `git config core.hooksPath script/hooks`) refuses a commit containing the team ID, the container, or a signing file.
- **Project:** `iOS/project.yml` generates `OpenUsageLight.xcodeproj` with XcodeGen (`cd iOS && xcodegen`), so no `.xcodeproj` is committed. This replaces the earlier idea of a hand-maintained project.
- **Code layout:** `OpenUsageSync` (the CloudKit record, shared by the Mac and the phone) and `OpenUsageMobile` (the dashboard model and SwiftUI screen) are package targets, because the core's API is `package`-scoped and an app outside the package could not use it.
- **First slice:** the Mac publishes; the phone app lists accounts and meters. Widgets, iPad layouts, and iPhone Duo come after (the Duo layout pages are still unread).

## Built so far

- `OpenUsageSync.CloudLimitsStore`: publish and fetch the record (compiles; not yet run against iCloud).
- `OpenUsageMobile`: `MobileAccount` (document to cards, tested), `MobileModel` (iCloud fetch, last saved document, example numbers when no container), `DashboardScreen`.
- `iOS/`: the app target, entitlements, and settings. Builds and runs in the iPhone simulator, showing example numbers.

## Next

1. The Mac publisher and a Settings switch. It needs a provisioning profile for the container, so the Mac dev build has to be signed with one.
2. Sign the simulator and Mac into the same iCloud account and check a publish reaches the phone.
3. Push notification on change (CloudKit subscription), then widgets.
4. Before any TestFlight build, deploy the CloudKit schema from Development to Production.
