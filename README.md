# OpenUsage Light [WIP]

> **Work in progress (0.1.0).** Sign-in has only been tested up to the provider's login page; no real account has been signed in end to end yet. Expect bugs.

OpenUsage Light is a native macOS menu-bar app for seeing usage limits across AI providers. It has no machine-local credential discovery, log scanning, or spend estimates: you add each account in the app, and it shows limits and dollar values returned by the provider's API.

## Accounts

Click Add Account in the menu-bar panel (or Settings → Accounts → Add Account), choose a provider, then complete its browser, device-code, or API-key sign-in. Browser sign-in shows Open in Browser and Copy Link, so you can pick which browser to use. You can add multiple accounts for the same provider, rename them, and remove them independently.

Account metadata is stored in the app's UserDefaults domain. OAuth tokens and API keys are stored in this app's own Keychain service. OpenUsage Light does not read credentials, files, Keychain items, databases, or environment variables belonging to other tools.

## Providers

The account picker supports Claude, Codex, Cursor, Antigravity, Copilot, Grok, Ollama, OpenCode Go, OpenRouter, and Z.ai. Providers use OAuth except Ollama, OpenCode Go, OpenRouter, and Z.ai, which use API keys.

The dashboard reports provider API usage limits, balances, and dollar values only when the provider reports them. No local model pricing or log-derived usage is used.

See [provider endpoints](docs/providers.md) for the sign-in and usage endpoints used by each provider.

## Building

Requires macOS 15 or later and Swift 6.2.

```sh
swift build
swift test
./script/build_and_run.sh verify
```

The development app is staged as `dist/OpenUsage Light.app` with bundle identifier `com.robinebers.openusage-light.dev`.

## Architecture

This SwiftPM app uses an AppKit status item and panel with SwiftUI content. `AccountStore` persists account metadata; `CredentialVault` stores each account's credential; `ProviderLogin` implements sign-in; and `AccountProviderRuntime` fetches and maps usage for one account. The dashboard is built from those runtimes and the account-specific metric layout.

See [docs/](docs/README.md) for behavior and development notes. `AGENTS.md` describes repository conventions.

## License

[MIT](LICENSE)
