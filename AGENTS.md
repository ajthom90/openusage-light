# AGENTS.md

OpenUsage Light is a SwiftPM-based menu-bar (macOS) and tray (Windows) app that displays usage limits for accounts users add within the app.

## Architecture

- Swift 6.2. On macOS, SwiftUI content hosted in an AppKit-owned status item and panel. On Windows, a Win32 tray icon and custom-painted popover.
- `AccountStore` persists account metadata. `CredentialVault` stores credentials in the app's own store: the Keychain service on macOS, DPAPI-encrypted files under `%APPDATA%` on Windows.
- Users initiate all provider sign-ins from the popover's Accounts screen. Never discover credentials or accounts from other tools, and never read their files, Keychain items, SQLite databases, or environment variables.
- Each account has one provider runtime. The runtime calls the provider API and maps its response to dashboard metrics. Do not add log scanning, spend estimates, or external pricing.
- The dashboard shows provider-supplied limits and dollar values only. Provider and account order is the user's saved order; a provider's first account goes to the bottom, and a new account goes to the bottom of its provider's accounts, in the order they were added. Never sort providers or accounts by catalog order or name.

## Targets

- `OpenUsageCore` (`Sources/OpenUsageCore`): the platform-neutral data model and the `openusage.limits.v1` document. It may import only Foundation (`CoreImportsTests` enforces this) and exposes its API as `package`. New code that does not need AppKit, SwiftUI, Keychain, or `os` belongs here, so a Windows or Linux app can reuse it; provider clients and mappers are the next candidates to move.
- `OpenUsage`: the macOS app library. `OpenUsageApp` is its executable shell.
- `OpenUsageWindows`, `OpenUsageWindowsApp`, `OpenUsageWindowsCLI`: the Windows build, declared in `Package.swift` only on Windows. `OpenUsageWindows` is the library (DPAPI vault, Win32 tray icon and popover, Winsock sign-in listener); the other two are the `OpenUsageLight` tray app and the `openusage` command. It must run on x64 and arm64. Its tests run in CI (`.github/workflows/windows.yml`), which also builds and exercises the installer (`script/installer.iss`, `script/package_windows.cmd`).
- `OpenUsageCLI`: the `openusage` command, a thin shell over `LimitsCommand`. The product is `openusage-cli` because macOS paths ignore case; the app installs a link named `openusage`. The command reads only this app's own accounts and Keychain items, and `build_and_run.sh` signs it with the app's identifier so it opens them without a prompt. It prints provider-reported limits only.

## Providers

Provider usage clients, mappers, and runtimes live under `Sources/OpenUsageCore/Providers/<Name>/`, and sign-in code under `Sources/OpenUsageCore/Login/`, so every platform shares them; only app-specific services (such as the macOS loopback listener) live under `Sources/OpenUsage/Services/`. Use `ProviderLogin` for sign-in and `AccountProviderRuntime` for account-scoped refresh. Provider API failures should surface as friendly account-specific errors without logging credentials or response bodies.

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
