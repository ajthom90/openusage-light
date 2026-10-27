# Windows app: design and plan

Status: **direction approved by the owner** ("go with your recommendation"; the app must run on both x64 and arm64). Everything under "My calls" is mine, not theirs, and is open to change.

## Intent

A native Windows app with the same job as the macOS one: a tray icon and a popover that show the usage limits of the accounts the user adds in the app, plus the `openusage` command. Same rules as the Mac app (AGENTS.md): sign-in only from inside the app, provider-reported numbers only, the user's saved order, no reading other tools' files or credentials.

## Goals

- Windows 11 and 10, **x64 and arm64** builds from the same source.
- The same providers, sign-ins, refresh cadence, and `openusage.limits.v1` output as macOS.
- Share code with the Mac app instead of forking it: one set of provider clients and mappers.

## Non-goals

- Linux (a later port; the shared core is built so it can follow).
- A Windows-only feature set. Anything the Mac app does not do stays out.
- A port of the Mac app's SwiftUI views.

## My calls

- **All Swift.** The Swift toolchain supports Windows on x86_64 and arm64 (official installers exist for both), and the provider code is already Swift and Foundation-only at the import level.
- **Native tray and popover, no web view.** A Win32 tray icon with a popover window, drawn natively.
- **UI toolkit:** to be chosen in Stage 4 by a short spike, not now. Candidates are Win32 through the `WinSDK` module directly, or the community `swift-win32` package. The deciding question is whether a good-looking, DPI-aware, dark-mode-aware popover is practical without a large dependency.
- **Dependencies:** only where there is no platform answer, each justified when added (likely `swift-crypto` for HMAC, SHA-256 and random bytes in place of `CryptoKit`).
- **Credentials:** Windows Credential Manager (`CredWrite`/`CredRead`) behind the existing `CredentialVault` protocol.
- **Account list and cache:** JSON files under `%APPDATA%\OpenUsage Light`, behind the same store interfaces the Mac app uses with `UserDefaults`.

## What blocks sharing today

The provider code imports only Foundation, but it calls helpers that live in the Mac app target:

| Helper | Why it is Apple-only | Plan |
| --- | --- | --- |
| `AppLog` / `LogTag` | wraps `os.Logger` | a small logging protocol in the core, `os` and file sinks per platform |
| `MetricFormatter`, `WidgetDescriptor`, `WidgetData` | display types, some use SwiftUI-adjacent code | keep display types in the app; give the runtime only the metric labels it needs |
| `ProviderParse`, `LogRedaction`, `Formatters` | Foundation-only, simply not moved yet | move into the core |
| `@MainActor` runtimes and `Observation` | the Mac view layer's concurrency model | keep runtimes actor-agnostic; the app hops to the main actor itself |
| `KeychainCredentialVault`, `CryptoKit` (PKCE) | Apple frameworks | per-platform implementations behind protocols |
| `LoopbackCallbackServer` (`Network`) | Apple framework | a portable loopback listener for the sign-in redirect |
| `URLSession` | Foundation on Windows ships it in `FoundationNetworking` | check behaviour, including TLS, on the VM |

## Stages (each ends with something proven on a real Windows machine)

1. **Toolchain and core build.** Install Swift and the MSVC build tools in the Windows 11 ARM64 VM. `OpenUsageCore` builds and its tests pass there. This tests the claim that the core is portable; if it fails, the failures are the first work items.
2. **Shared engine.** Move the provider clients, mappers, runtime, HTTP client, credential and store protocols, and the limits service into the core, behind the helpers above. The Mac app and tests stay green throughout. At the end `openusage` can be built from the core alone.
3. **Windows platform layer.** Credential Manager vault, file-backed stores, logging, loopback listener, crypto. Prove it by building and running `openusage` on Windows against a real API-key provider.
4. **Tray and popover.** The UI spike, then the dashboard, Accounts screen, sign-in flows, reorder, settings, launch at login.
5. **Packaging.** An installer or MSIX for x64 and arm64, signing, and updates. Needs the owner's decisions on certificates and distribution.

## What I can and cannot verify

- **arm64:** testable on the owner's Parallels "Windows 11" VM (Windows 11 ARM64).
- **x64:** there is no x64 Windows machine reachable from this Mac. The x64 build will be cross-built for the arm64 VM and run under its x64 emulation, which checks that it builds and starts but not native x64 behaviour. The owner has noted an x64 machine elsewhere; real x64 testing needs access to it.
- Nothing here can be verified against real provider accounts on Windows until sign-in exists (Stage 3 for API-key providers, later for OAuth).

## Open questions for the owner

- Installer format and signing: unsigned MSI/zip for now, or a signing certificate?
- Auto-update: wanted for Windows, and if so through what?
- Minimum Windows version: 11 only, or 10 too?

## Progress

- **Stage 1, arm64: done (2026-10-27).** Swift 6.4.1 (`aarch64-unknown-windows-msvc`) and the Visual Studio 2022 Build Tools (x64 and ARM64 C++ tools, Windows 11 SDK) are installed in the Parallels "Windows 11" VM. `OpenUsageCore` builds there and all of `OpenUsageCoreTests` pass (16 XCTest, 3 Swift Testing). The manifest declares only the core and its tests off macOS.
- **Stage 1, x64: not started.** Waiting on SSH access to the owner's x64 machine. The arm64 toolchain can't build an x64 binary without an x64 Swift SDK, so this needs the real machine.
- **Working notes.** Source reaches the VM as a base64 archive through `prlctl exec` (arguments over ~3 KB fail; the host's folders are not shared). Pack with `COPYFILE_DISABLE=1`, or macOS `tar` adds `._*` metadata files that break the UTF-8 import test. Builds run through `vcvarsall.bat arm64` first.
