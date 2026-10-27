# Muse Code usage tracking: findings and open questions

Status: **the usage request is confirmed against a real account and is safe to poll. Implementation under way.** Findings are from Meta's public pages read on 2026-10-27.

## What Muse Code is

Meta's coding agent (a rival to Claude Code and Codex), sold as monthly plans with usage allowances that reset on a five-hour cycle.

| Plan | Price | Allowance, per Meta's product page |
| --- | --- | --- |
| Everyday | $5.00/month | "Send 10-50 prompts every 5 hours" |
| High | $15.00/month | "5x more usage than the Everyday Usage plan" |
| Power | $50.00/month | "20x more usage than the Everyday Usage plan" |
| Maximum | $200.00/month | "80x more usage than the Everyday Usage plan" |

Third-party articles quote different multipliers (3x/10x) for the first tiers and disagree on whether the $200 tier exists; Meta's own page, read directly, lists the four tiers above.

## How a user signs in (from the docs page)

On first run the CLI offers "a browser sign-in or an API key". `/login` reopens those options. CI is told to set `META_API_KEY`. The browser flow goes to a single-sign-on provider. The docs page does not say where credentials are stored.

## What the docs say about usage (read 2026-10-27)

- **Subscription usage is metered in prompts per window, not tokens.** [Subscriptions](https://dev.meta.ai/docs/muse-code/subscriptions): Everyday is "10-50 prompts every 5 hours, including image and video uploads"; higher plans are 5x, 20x, and 80x. The page does not say how a prompt is counted or when the window resets, and it documents **no way to query remaining usage**. `/upgrade` opens accountscenter.meta.com; `/settings` covers Contributor mode.
- **The CLI can show it.** The changelog says Muse Code **1.4.13** added "`muse usage` shows your subscription allowance (window and weekly use, reset times, tier) without running a model turn", plus warnings near the limit. 1.4.11 added `muse exec --json` with a `run.usage` line that "includes your subscription allowance", and a `/usage` slash command. (The changelog gives no dates, and only the first 100,000 of its 186,663 characters were read.) So Meta's backend serves this data to a signed-in client; **the endpoint is not documented.**
- **Pay-as-you-go API usage:** the Meta Model API returns a per-response `usage` object (token counts) and `x-ratelimit-limit/remaining-tokens/requests` headers. Those are per-minute rate limits per team, not a subscription meter, and reading them means making a billed model request. There is no usage or quota query endpoint ([rate limits](https://dev.meta.ai/docs/pricing-rate-limits)).
- **The SDK does not help.** `@muse-code/sdk` and the Muse Session Protocol talk to a local `muse` binary, which does its own sign-in and network calls. The SDK docs describe no usage, allowance, or account methods (the generated wire-method reference was not read).
- **Sign-in** ([auth](https://dev.meta.ai/docs/muse-code/auth)): browser sign-in ("opens a browser to approve the session") or an API key (`META_API_KEY`, or `muse auth set`). Meta Managed Account users must use an API key. Storage location, the sign-in protocol, endpoints, and the API-key header are not documented.

## Fit with the project rules (AGENTS.md)

- Usage must come from a provider API the app calls with a sign-in the user performs in the app.
- The app must not read the Muse Code CLI's saved credentials, files, or environment (`META_API_KEY` included), and must not scan its logs.
- No estimates: counting prompts and dividing by an allowance such as "10-50 prompts" would be an estimate, so a usage meter needs Meta to report used and limit.

## What the CLI itself shows (checked 2026-10-27 on the owner's installed 1.4.13 and their test account)

All of this came from the CLI's own output, its offline `muse schema`, and text in its launcher script and binary. No credentials were read.

- `muse usage --json` prints, after one model turn: `{"allowance":{"tier":"Muse Code Power Usage","window":{"usedPercent":2,"resetsAtMs":...},"weekly":{"usedPercent":0,"resetsAtMs":...},"asOfMs":...,"source":"mint"}}`. Before any turn it printed `"allowance":null,"reason":"server_sent_no_usage"`.
- Meta's wire schema (`SubscriptionUsage`) defines it: plan `tier`, a 5-hour-class `window` (`usedPercent`, `resetsAtMs`, `windowDurationMins`) and a rolling `weekly` block (`usedPercent`, `resetsAtMs`). Percentages are integers that may exceed 100. That is the same two-meter shape the app already draws for Claude and Codex.
- **`source: "mint"`**: the usage arrives with the "mint" request, the call that turns the browser sign-in into a working key. The binary's `MintedKey` structure has 15 fields, including `api_key`, `is_subs_active`, `subs_tier_id`, `subs_tier_name`, `has_payment_method`, `can_subscribe`, `subs_usage`, `user_full_name`, `user_email`. The binary reads `TBH_MINT_BASE_URL` to override the mint service's base URL, and uses `https://api.meta.ai/v1` for the model API.
- **Sign-in is the standard OAuth device flow** against `https://auth.meta.com`: `POST /oidc/device/authorization/` and `POST /oidc/device/token/` with the public client id `1031625952748946` and the grant `urn:ietf:params:oauth:grant-type:device_code` (from the launcher script; the same client id appears beside `MintedKey` in the binary). The app already implements this flow for Copilot, Grok, and Cursor.
- Route fragments seen in the binary under `https://api.meta.ai/muse-code/`: `config`, `key`, `models`, `search`, `telemetry/...`, `logout`. **`muse-code/key` is a guess for the mint route; its method, headers, and exact response keys are unconfirmed.**

## What a real implementation needs

1. **Sign-in in the app:** the device flow above (the app's existing `DeviceCodePoller` pattern), producing a token the app stores in its own vault. No reading of `~/.config/muse/auth.json`.
2. **The mint call** with that token, then read `subs_usage` (window and weekly) plus `subs_tier_name`. Confirm the route, method, and response keys by making the call once with an app-obtained token.
3. **Caveats:** the mint endpoint is undocumented and can change; it may mint a new API key each time it is called (side effects not yet known); whether the launcher's client id is accepted for this scope is unverified.
4. **Not acceptable:** running `muse usage` as a subprocess or reading the CLI's stored credentials.

## Confirmed against a real account (2026-10-27)

A throwaway script (stdlib only, nothing stored, secrets redacted) ran the device flow with the owner's test Meta AI account, then called the mint route:

- **Sign-in:** `POST https://auth.meta.com/oidc/device/authorization/` with `client_id=1031625952748946` (form-encoded) returns a code and `https://auth.meta.com/oauth/device/?code=XXXX-XXXX`, valid 600 s. Polling `POST /oidc/device/token/` with the device-code grant returns `{access_token, token_type}`: **no scope, no `expires_in`, no refresh token.** How long the token lives is unknown.
- **Usage:** `POST https://api.meta.ai/muse-code/key` with `Authorization: Bearer <that token>` and an empty form body returns HTTP 200. (`GET` on the same route is 405 "No path defined with the given http verb".) JSON fields: `api_key` (secret), `base_url` (`https://api.meta.ai/v1`), `is_subs_active`, `can_subscribe`, `show_subs_upsell`, `is_subs_upgrade_available`, `has_payment_method`, `require_payment`, `payment_method`, `action_url`, `subs_tier_id`, `subs_tier_name` ("Muse Code Power Usage"), the account's name, email and avatar (not to be shown or logged), and
  `subs_usage: { window: { used_percent: 30, window_duration_mins: 300, resets_at: <epoch seconds> }, weekly: { used_percent: 10, resets_at: <epoch seconds> }, tier: <id> }`.
  Percentages are integers; `resets_at` is in **seconds** (the CLI's own `resetsAtMs` is milliseconds).
- `GET /muse-code/config` with the sign-in token returns 401 "Invalid or expired API key": other routes want the *minted* key, not the sign-in token.

## Does each call mint a new key? No.

A second probe signed in once and called the mint route twice, two seconds apart, comparing the returned `api_key` by a hash prefix (no key value printed): **the key was identical both times**, and both calls returned the same live usage (37% of the window, 12% weekly; the first probe had seen 30% and 10%). So the call is idempotent for a given sign-in, and polling on the shared five-minute interval does not create keys. *Tested only for two calls seconds apart.*

## Plan

1. `MuseCodeLogin` (device flow, same shape as `GrokLogin`/`CopilotLogin`) storing the sign-in token in the app's own vault.
2. A `ProviderKind.musecode` with `MuseCodeUsageClient` (the mint call) and `MuseCodeUsageMapper`: a "Session" meter from `window` (percent, `window_duration_mins`), a "Weekly" meter from `weekly`, plan from `subs_tier_name`. Treat `used_percent > 100` as over quota.
3. Friendly errors: 401/403 means sign in again; `require_payment` or an inactive subscription is shown as a notice, not an error.
4. Resource keys `session` and `weekly` in `LimitsProjection`, an icon, a README line, and tests with stubbed responses.

## Sources

- <https://dev.meta.ai/products/muse-code/>
- <https://dev.meta.ai/docs/muse-code/>
- <https://dev.meta.ai/docs/muse-code/subscriptions>
- <https://dev.meta.ai/docs/muse-code/auth>
- <https://dev.meta.ai/docs/muse-code/changelog>
- <https://dev.meta.ai/docs/pricing-rate-limits>
- <https://meta-models.github.io/muse-code-sdk/1.4/>
- <https://www.subscriptioninsider.com/blog/meta-adds-monthly-plans-as-muse-code-exits-beta>
