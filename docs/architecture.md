# Architecture

OpenUsage Light is a SwiftPM macOS menu-bar app. SwiftUI screens run in an AppKit status item and key-capable panel. `AppContainer` composes the account store, provider runtimes, widget registry, layout, and refresh loop.

## Account data

`AccountStore` persists account metadata in UserDefaults under `accounts.v1`. Each account has a stable UUID and provider-specific card ID. `CredentialVault` stores OAuth tokens or API keys in this app's Keychain service, keyed by account UUID. Removing an account removes its credential.

`ProviderLogin` handles user-initiated authentication. `ProviderCatalog` builds one `AccountProviderRuntime` per saved account, ordered by provider and account creation time. Runtime refreshes may rotate tokens; refreshed credentials are written back to the vault.

## Usage pipeline

Each account runtime calls its provider's official usage API, maps API responses to `MetricLine` values, and returns a `ProviderSnapshot`. The dashboard renders normalized metrics through `WidgetDescriptor`s. Only provider-reported limits and dollar values are shown; there is no local log scanning, credential discovery, or local pricing.

The main source folders are:

- `App/` — app startup, container, and AppKit menu-bar bridge.
- `Models/` — accounts, credentials, metric values, snapshots, and descriptors.
- `Providers/` — provider API clients and response mappers.
- `Services/` — account login, credential vault, HTTP, and refresh helpers.
- `Stores/` — persisted accounts, layout, snapshots, and settings.
- `Views/` — dashboard, Customize, Settings, and account management.

## Stores

- `AccountStore` owns account metadata and coordinates credential writes/deletes.
- `WidgetDataStore` owns cached provider snapshots and refresh state.
- `LayoutStore` stores ordered, visible, and pinned account metrics.

## Adding a provider

Implement the account login and usage runtime, declare the provider's metric descriptors, then add tests and a concise behavior page. See [Adding a Provider](adding-a-provider.md).

## Platform support

The app supports macOS 15 and later. The development build uses the host architecture and bundle identifier `com.robinebers.openusage-light.dev`.
