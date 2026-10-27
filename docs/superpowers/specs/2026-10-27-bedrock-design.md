# Amazon Bedrock (Claude Code) usage: design notes

Status: **draft, not approved.** Nothing is built. This records what is known and what only the owner can decide, so work can start from here.

## Intent

Show, in the menu-bar dashboard and in `openusage`, how much Claude is being used through Amazon Bedrock, so someone who runs Claude Code against Bedrock sees it next to their Claude, Codex and Cursor accounts.

## Constraints from the project (AGENTS.md)

- Sign-in happens in the app's Accounts screen. Never read `~/.aws`, `AWS_PROFILE`, `AWS_*` variables, or any other tool's files or Keychain items.
- Show only what the provider's API reports. **No spend estimates**: tokens multiplied by a price is an estimate and is not allowed. Dollars must be an amount AWS itself reports.
- No log scanning. Claude Code's own logs and OpenTelemetry output are off limits.
- Friendly, account-specific errors; never log credentials or response bodies.
- Account and provider order is the user's saved order.
- The CLI's `openusage.limits.v1` document needs resource keys for the new provider (see `LimitsProjection`).

## What AWS can report (to verify against the AWS docs before building)

| Source | Gives | Cost and freshness |
| --- | --- | --- |
| CloudWatch `AWS/Bedrock` metrics (`InputTokenCount`, `OutputTokenCount`, `Invocations`, by `ModelId`) | Token counts over a window, per model | Near-live; `GetMetricData` is billed per metric requested, so cheap at a five-minute cadence |
| Cost Explorer `GetCostAndUsage` | Billed dollars for Bedrock, grouped by usage type | Billed per request, and lags about a day, so a five-minute poll would pay for stale data |
| Service Quotas (`bedrock`) | The account's token and request limits | Free; a limit, not a usage figure |

A meter needs a used amount and a limit. The natural pair is CloudWatch tokens (used) against a Service Quotas limit for the same model family, if a matching quota exists. That pairing is unverified.

## Open decisions (the owner's)

1. **Which numbers?** Tokens, billed dollars, quota usage, or a combination. Tokens plus quota gives a real meter; dollars give "what did this cost" but lag and cost per call.
2. **Claude Code, or all Claude on Bedrock?** AWS cannot tell which client made a call. Metrics see `anthropic.claude-*` models, not Claude Code. Isolating Claude Code means a dedicated IAM user or an application inference profile that Claude Code is pointed at. Without that, the account is "all Claude usage in this AWS account".
3. **Sign-in shape.** AWS has no OAuth. Pasted access key ID, secret, region, and an optional session token is the only option that respects the no-discovery rule. Short-lived SSO or session credentials would need re-entry when they expire.
4. **Cadence.** Whether to refresh on the shared five-minute interval or slower for the metered sources.

## What the work involves

- A new credential case. `AccountCredential` has only `.oauth` and `.apiKey(String)`; Bedrock needs several stored fields.
- A multi-field sign-in sheet. `ProviderAuthMethod.apiKey(keyPage:)` drives a single-field sheet today.
- SigV4 request signing (HMAC-SHA256). `CryptoKit` provides it on Apple platforms, like `PKCE`; a Windows or Linux port would need its own.
- A provider runtime and mapper under `Sources/OpenUsage/Providers/Bedrock/`, a `ProviderKind` case, a catalog entry, an icon, and resource keys in `LimitsProjection`.
- Tests with stubbed AWS responses. **There is no AWS account here to check the real service**, so the first version would be verified against documented response shapes only.

## Suggested defaults if the owner says "just pick"

- Tokens from CloudWatch for Anthropic models over the last 24 hours, against the matching Service Quotas daily token limit when one exists, otherwise tokens shown without a bar.
- Whole-account scope, labelled as such, with a note on how to isolate Claude Code.
- Pasted access key, secret, region, and optional session token.
- No Cost Explorer in the first version.

## Not decided here

Pricing, release timing, and whether a dedicated "Bedrock" icon is needed.
