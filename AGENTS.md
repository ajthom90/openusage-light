# AGENTS.md

OpenUsage Light is a SwiftPM-based macOS menu-bar app that displays usage limits for accounts users add within the app.

## Architecture

- Swift 6.2, SwiftUI content hosted in an AppKit-owned status item and panel.
- `AccountStore` persists account metadata. `CredentialVault` stores credentials in the app's own Keychain service.
- Users initiate all provider sign-ins from the popover's Accounts screen. Never discover credentials or accounts from other tools, and never read their files, Keychain items, SQLite databases, or environment variables.
- Each account has one provider runtime. The runtime calls the provider API and maps its response to dashboard metrics. Do not add log scanning, spend estimates, or external pricing.
- The dashboard shows provider-supplied limits and dollar values only. Provider and account order is the user's saved order; a provider's first account goes to the bottom, and a new account goes to the bottom of its provider's accounts, in the order they were added. Never sort providers or accounts by catalog order or name.

## Providers

Provider sign-in and usage code lives under `Sources/OpenUsage/Providers/<Name>/` and `Sources/OpenUsage/Services/`. Use `ProviderLogin` for sign-in and `AccountProviderRuntime` for account-scoped refresh. Provider API failures should surface as friendly account-specific errors without logging credentials or response bodies.

## Running and Testing

```sh
swift build
script/test_quiet.sh [--filter <Suite>]
./script/build_and_run.sh verify
```

`script/test_quiet.sh` is the only way to run the tests on a Mac someone is using: the suite hosts real windows, and the script runs it niced, keeps it from taking the keyboard or the screen, and fails if it ever did. A test that hosts a window subclasses `QuietWindowTestCase` and shows it through `QuietTestProcess.show`; the few that need a key window skip unless `OPENUSAGE_FOCUS_TESTS=1`.

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
