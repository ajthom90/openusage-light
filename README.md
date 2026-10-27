# OpenUsage Light [WIP]

> **Work in progress (0.1.0).** Sign-in has only been tested up to the provider's login page; no real account has been signed in end to end yet. Expect bugs.

OpenUsage Light is a native macOS menu-bar app for seeing usage limits across AI providers. It has no machine-local credential discovery, log scanning, or spend estimates: you add each account in the app, and it shows limits and dollar values returned by the provider's API.

## Accounts

Open Accounts from the menu-bar panel's Options menu (or press Return), click the + at the top, and click a provider (or select it with the arrow keys and press Return) to go straight to its browser, device-code, or API-key sign-in. Browser sign-in shows Open Browser and Copy Link, so you can pick which browser to use. If sign-in fails, Try Again starts it over. You can add multiple accounts for the same provider.

To rename an account, double-click its name on the dashboard, choose Rename from its right-click menu, or click the name at the top of its page in Accounts. The field opens with the whole name selected, so typing replaces it. Return or a click elsewhere saves the new name, and Esc cancels. Remove Account is at the bottom of the account's page in Accounts.

Account metadata is stored in the app's UserDefaults domain. OAuth tokens and API keys are stored in this app's own Keychain service. OpenUsage Light does not read credentials, files, Keychain items, databases, or environment variables belonging to other tools.

## Providers

The account picker supports Claude, Codex, Cursor, Antigravity, Copilot, Grok, Ollama, OpenCode, OpenRouter, and Z.ai. Providers use OAuth except Ollama, OpenCode, OpenRouter, and Z.ai, which use API keys: none of them offers a sign-in that the app can use to read usage. Each API-key step links to the page where you create the key. OpenRouter's balance needs a Management key.

The dashboard reports provider API usage limits, balances, and dollar values only when the provider reports them. No local model pricing or log-derived usage is used.

The dashboard has a header and a card per provider. The header names the provider, and the account too when there is one with a name of its own ("Codex — Sunstory") that fits the line, with its plan and the provider's logo at the right end; nothing is ever cut short, so a name that does not fit goes inside the card with its plan, the way several accounts are shown. The card holds every metric that has data, in the order you set, one row each: the label, a bar that fills with what is left (blue; orange once 80% is used; red once 90% is), the percentage, and the time to the reset; a flame appears before the percentage while you are using the limit faster than it resets (orange when you are on course to land within the last 10%, red when you are on course to run out before the reset); a balance or a count shows its value in the bar's place. When a provider has several accounts, each is named inside the card above its rows, with its plan at the right. Nothing on a row reacts to the pointer. While the pointer is on a provider, its logo becomes a button that copies a picture of that provider's header and card; the picture uses the account's name when you have set one and leaves an email out. Settings → Usage Display chooses whether usage reads as used or left, and whether reset times read as countdowns or exact times.

Right-click for actions:

- A provider's header or card: Refresh, Manage Accounts…, and the provider's links, such as Status Page and Usage Dashboard.
- An account: Refresh, Rename, Edit Account…, and Share Screenshot. If the account's name shows a warning or stale icon, the menu starts with the reason. Show Hidden Metrics appears when you have hidden any.
- A metric: Star for Menu Bar (or Unstar) and Hide. Hiding a metric, here or on the Accounts screen, also takes its star off the menu bar. Starring a hidden metric shows it again.

On a provider with one account, the menu combines the two: the warning reason if there is one, Refresh, Rename, Edit Account…, Manage Accounts…, Share Screenshot, Show Hidden Metrics, and the provider's links.

Drag a provider by its header, an account by its name, or a metric by its row to reorder them. A new provider goes to the bottom of the dashboard and the Accounts list, and a new account goes to the bottom of its provider's accounts.

When the menu bar shows more than one account of a provider, each mark carries a two-character tag from the account's name. The tag keeps the account's number, so "Attention Machine 1" and "Attention Machine 2" read A1 and A2. Names that would share a tag show the first letter that differs, such as WO and WE for Work and Web.

Claude and Codex accounts show a Limit Resets row with the number of available rate-limit resets while they have any. Rest the pointer on the count for a moment to see when each reset expires. To spend one, hover its line there, choose Use, then Reset.

## Building

Requires macOS 15 or later and Swift 6.2.

```sh
swift build
script/test_quiet.sh
./script/build_and_run.sh verify
```

`script/test_quiet.sh` runs the tests without letting them take the keyboard or show a window on the Mac they run on; it takes `swift test` arguments such as `--filter`.

The development app is staged as `dist/OpenUsage Light.app` with bundle identifier `com.robinebers.openusage-light.dev`.

## Architecture

This SwiftPM app uses an AppKit status item and panel with SwiftUI content. `AccountStore` persists account metadata; `CredentialVault` stores each account's credential; `ProviderLogin` implements sign-in; and `AccountProviderRuntime` fetches and maps usage for one account. The dashboard is built from those runtimes and the account-specific metric layout.

`AGENTS.md` describes repository conventions.

## License

[MIT](LICENSE)
