# OpenUsage Light [WIP]

> **Work in progress (0.1.0).** Sign-in has only been tested up to the provider's login page; no real account has been signed in end to end yet. Expect bugs.

OpenUsage Light is a native macOS menu-bar app for seeing usage limits across AI providers. It has no machine-local credential discovery, log scanning, or spend estimates: you add each account in the app, and it shows limits and dollar values returned by the provider's API.

## Accounts

Open Accounts from the menu-bar panel's Options menu (or press Return), click the + at the top, choose a provider, then complete its browser, device-code, or API-key sign-in. Browser sign-in shows Open Browser and Copy Link, so you can pick which browser to use. If sign-in fails, Try Again starts it over. You can add multiple accounts for the same provider.

To rename an account, double-click its name on the dashboard, choose Rename from its right-click menu, or click the name at the top of its page in Accounts. The field opens with the whole name selected, so typing replaces it. Return or a click elsewhere saves the new name, and Esc cancels. Remove Account is at the bottom of the account's page in Accounts.

Account metadata is stored in the app's UserDefaults domain. OAuth tokens and API keys are stored in this app's own Keychain service. OpenUsage Light does not read credentials, files, Keychain items, databases, or environment variables belonging to other tools.

## Providers

The account picker supports Claude, Codex, Cursor, Antigravity, Copilot, Grok, Ollama, OpenCode, OpenRouter, and Z.ai. Providers use OAuth except Ollama, OpenCode, OpenRouter, and Z.ai, which use API keys.

The dashboard reports provider API usage limits, balances, and dollar values only when the provider reports them. No local model pricing or log-derived usage is used.

The dashboard has one card per provider. Each account shows its name with its plan as a tag on the right, then every metric that has data, in the order you set. When a provider has only one account, the card's header shows that account's name next to the logo, with its tags on the right, and the metrics follow straight below. Apart from the ↺ tag and a double-click on an account's name, nothing on the dashboard reacts to hover or a click. Settings → Usage Display chooses whether usage reads as used or left, and whether reset times read as countdowns or exact times.

Right-click for actions:

- A provider's card: Refresh, Manage Accounts…, and the provider's links, such as Status Page and Usage Dashboard.
- An account: Refresh, Rename, Edit Account…, and Share Screenshot. If the account line shows a warning or stale icon, the menu starts with the reason. Show Hidden Metrics appears when you have hidden any.
- A metric: Star for Menu Bar (or Unstar) and Hide.

On a card with one account, the header's menu combines the two: the warning reason if there is one, Refresh, Rename, Edit Account…, Manage Accounts…, Share Screenshot, Show Hidden Metrics, and the provider's links.

Drag a card by its header, an account by its name, or a metric by its line to reorder them. A new provider goes to the bottom of the dashboard and the Accounts list, and a new account goes to the bottom of its provider's accounts.

When the menu bar shows more than one account of a provider, each mark carries a two-character tag from the account's name. The tag keeps the account's number, so "Attention Machine 1" and "Attention Machine 2" read A1 and A2. Names that would share a tag show the first letter that differs, such as WO and WE for Work and Web.

Claude and Codex accounts show a ↺ tag with the number of available rate-limit resets. It turns orange when the soonest one expires within 7 days and red within 48 hours. Hover or click the tag to see when each reset expires. To spend one, hover its row, choose Use, then Reset.

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

`AGENTS.md` describes repository conventions.

## License

[MIT](LICENSE)
