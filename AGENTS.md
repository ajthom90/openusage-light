# AGENTS.md

OpenUsage Light is a SwiftPM-based macOS menu-bar app that displays usage limits for accounts users add within the app.

## Architecture

- Swift 6.2, SwiftUI content hosted in an AppKit-owned status item and panel.
- `AccountStore` persists account metadata. `CredentialVault` stores credentials in the app's own Keychain service.
- Users initiate all provider sign-ins from Settings → Accounts. Never discover credentials or accounts from other tools, and never read their files, Keychain items, SQLite databases, or environment variables.
- Each account has one provider runtime. The runtime calls the provider API and maps its response to dashboard metrics. Do not add log scanning, spend estimates, external pricing, or reset-claim actions.
- The dashboard shows provider-supplied limits and dollar values only. Keep provider order and account order defined in `ProviderCatalog`.

## Providers

Provider sign-in and usage code lives under `Sources/OpenUsage/Providers/<Name>/` and `Sources/OpenUsage/Services/`. Use `ProviderLogin` for sign-in and `AccountProviderRuntime` for account-scoped refresh. Provider API failures should surface as friendly account-specific errors without logging credentials or response bodies.

## Running and Testing

```sh
swift build
swift test
./script/build_and_run.sh verify
```

The app is long-lived; rebuild and restart it when validating app changes. The development bundle identifier is `com.robinebers.openusage-light.dev`.

## Documentation

Update `README.md` when behavior changes. Keep it plain, brief, and focused on account sign-in and API-reported usage. Remove documentation for features that are no longer present.

## Code Conventions

- Keep files under roughly 500 lines; split focused concerns when needed.
- Follow existing Swift formatting and strict-concurrency conventions.
- Validate user input and provider API responses at the boundary.
- Add a focused regression test for behavior changes.
- Use title case for hardcoded UI titles and match the existing macOS design language.
- Do not add dependencies without a clear need.
