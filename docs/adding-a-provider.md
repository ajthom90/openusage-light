# Adding a Provider

Each account is authenticated by a `ProviderLogin` and refreshed by an account-scoped `AccountProviderRuntime`.

## Sign-in

Use `ProviderKind.authMethod` to distinguish OAuth from API-key providers. OAuth flows belong in `Services/` and should use the shared PKCE, device-code, and loopback helpers where applicable. A login returns a display label and one `AccountCredential`; `AccountsSettingsSection` then saves both through `AccountStore`.

Never inspect another tool's files, Keychain items, databases, or environment variables. Sign-in must be explicit and initiated by the user. Check cancellation and validate provider responses before saving credentials.

## Usage

Build one runtime for a single `Account`. Load its credential from `CredentialVault`, call the provider usage API, and map provider-reported data to `MetricLine` values. Persist rotated OAuth tokens through the vault. Do not infer dollar values from local usage logs or external pricing.

Add account-specific metric descriptors to the provider's widgets. Use the account's `cardID` so separate accounts have independent layout and snapshots. Keep provider and metric order consistent with `ProviderKind.allCases`.

## Tests and docs

Add tests for login response mapping, account persistence, token refresh, and usage mapping. Use stub HTTP responses; tests must not require user credentials or make live provider requests. Update the architecture or dashboard documentation when behavior changes.
