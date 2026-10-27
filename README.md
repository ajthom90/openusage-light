# OpenUsage Light [WIP]

> **Work in progress (0.1.0).** Sign-in has only been tested up to the provider's login page; no real account has been signed in end to end yet. Expect bugs.

OpenUsage Light is a native macOS menu-bar app for seeing usage limits across AI providers. It has no machine-local credential discovery, log scanning, or spend estimates: you add each account in the app, and it shows limits and dollar values returned by the provider's API.

## Accounts

Open Accounts from the menu-bar panel's Options menu (or press Return), click the + at the top, and click a provider (or select it with the arrow keys and press Return) to go straight to its browser, device-code, or API-key sign-in. Browser sign-in shows Open Browser and Copy Link, so you can pick which browser to use. If sign-in fails, Try Again starts it over. You can add multiple accounts for the same provider.

To rename an account, double-click its name on the dashboard, choose Rename from its right-click menu, or click the name at the top of its page in Accounts. The field opens with the whole name selected, so typing replaces it. Return or a click elsewhere saves the new name, and Esc cancels. Remove Account is at the bottom of the account's page in Accounts.

Account metadata is stored in the app's UserDefaults domain. OAuth tokens and API keys are stored in this app's own Keychain service. OpenUsage Light does not read credentials, files, Keychain items, databases, or environment variables belonging to other tools.

## Command Line

`openusage` prints the limits your accounts report, as JSON, and exits. It reads the accounts you added in the app, so it needs no sign-in of its own and the app does not have to be running.

```sh
openusage                  # every account, refreshing results older than five minutes
openusage codex            # every Codex account
openusage codex@86802bcd   # one account, by the id listed in "order"
openusage --force          # refresh now instead of reusing recent results
```

Install it from Settings → Command Line, which links `/usr/local/bin/openusage` to the helper inside the app, so app updates update the command. Exit codes are `0` for success, `2` for invalid arguments or an unknown provider, and `4` when a refresh failed; the last good results are still printed, with the failure listed in `errors`.

The output is the `openusage.limits.v1` document: `order` lists the account ids in your dashboard order, and `providers` maps each id to its plan, `fetchedAt`, `expiresAt`, `stale`, and a `resources` object. A resource is either `consumption` (`used`, plus `limit`, `remaining`, `utilization` and `resetsAt` when the provider reports them) or `balance` (`available`), with an explicit `unit`. Only provider-reported numbers appear; a resource the provider did not report is left out. Credentials never appear.

## Windows

The Windows app lives in the notification area and opens the same dashboard. Add accounts from its Accounts screen, as on the Mac; credentials are stored encrypted for your Windows user (DPAPI) under `%APPDATA%\OpenUsage Light`. It runs on x64 and arm64.

Download `OpenUsageLight-Setup.exe` from the Windows workflow's artifacts and run it. It installs for your user only, with optional "Start with Windows" and "Add the openusage command to my PATH" choices. The installer is unsigned, so SmartScreen will warn. The `openusage` command works as described above and reads the accounts you added in the app.

To build on Windows, install Swift and the Visual Studio build tools, then run `swift build`; `script\package_windows.cmd` makes the zip that `script/installer.iss` wraps.

## Providers

The account picker supports Claude, Codex, Cursor, Antigravity, Copilot, Grok, Muse Code, Ollama, OpenCode, OpenRouter, and Z.ai. Providers use OAuth except Ollama, OpenCode, OpenRouter, and Z.ai, which use API keys: none of them offers a sign-in that the app can use to read usage. Each API-key step links to the page where you create the key. OpenRouter's balance needs a Management key. Muse Code (Meta) signs in with a code you approve in the browser and shows its 5-hour and weekly allowance as Session and Weekly; Meta documents no usage endpoint for it, so this relies on the same request Muse Code's own sign-in makes and may change without notice.

The dashboard reports provider API usage limits, balances, and dollar values only when the provider reports them. No local model pricing or log-derived usage is used.

The dashboard has a header and a card per provider. The header shows the provider's logo and name, and inside the card every account, even when it is the only one, has a caption with its name and plan above its rows. The card holds every metric that has data, in the order you set, one row each: the label, a bar that fills with what is left, the percentage in the bar's colour, and the time to the reset. The colour is where your pace lands at the reset: blue while on course, orange when on course to land within the last 10%, red when on course to run out before the reset, with a flame before the percentage in that case; a metric with no reset window colours by its level instead (orange once 75% is used, a quarter left; red once 90% is). A balance or a count shows its value in the bar's place. Nothing on a row reacts to the pointer; a warning or clock after an account's name explains itself when you rest the pointer on it. Click any bar row's value to flip every row between used and left, and any reset time to flip between a countdown and the exact time; Settings → Usage Display holds the same two switches.

Right-click for actions:

- A provider's header or card: Refresh, Manage Accounts…, Share Screenshot, and the provider's links, such as Status Page and Usage Dashboard.
- An account: Refresh, Rename, Edit Account…, and Share Screenshot. If the account's name shows a warning or stale icon, the menu starts with the reason. Show Hidden Metrics appears when you have hidden any.
- A metric: Star for Menu Bar (or Unstar) and Hide. Hiding a metric, here or on the Accounts screen, also takes its star off the menu bar. Starring a hidden metric shows it again.

Share Screenshot copies a picture to the clipboard: from a provider's header, its whole card with every account; from an account, that account alone. The picture uses the account's name when you have set one and leaves an email out. Share Screenshot is on these right-click menus only: the footer's Options menu holds Accounts, Settings, Report an Issue…, About OpenUsage, and Quit OpenUsage.

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

This SwiftPM package has three code targets. `OpenUsageCore` holds the platform-neutral data model and the limits document (Foundation only, so a Windows or Linux app can build on it); `OpenUsage` is the macOS app library; `OpenUsageCLI` is the `openusage` command. On Windows the package adds `OpenUsageWindows` (library), `OpenUsageWindowsApp` (the tray app), and `OpenUsageWindowsCLI`. A test fails if `OpenUsageCore` imports anything but Foundation. Provider clients, mappers, runtimes, and sign-in logic live in the core too, so every platform shares them.

The app uses an AppKit status item and panel with SwiftUI content. `AccountStore` persists account metadata; `CredentialVault` stores each account's credential; `ProviderLogin` implements sign-in; and `AccountProviderRuntime` fetches and maps usage for one account. The dashboard is built from those runtimes and the account-specific metric layout.

`AGENTS.md` describes repository conventions.

## License

[MIT](LICENSE)
