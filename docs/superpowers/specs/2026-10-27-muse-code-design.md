# Muse Code usage tracking: findings and open questions

Status: **no documented usage API; an undocumented one exists. Nothing built.** Findings are from Meta's public pages read on 2026-10-27.

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

## What a real implementation needs

1. **The endpoint behind `muse usage`:** its URL, the auth it expects, and its response shape. This is the same kind of first-party-but-undocumented endpoint the app already uses for other providers' usage (for example Claude's `/api/oauth/usage`), so it fits the project's pattern, but it can change without notice.
2. **A sign-in the app can run itself** (AGENTS.md: sign-in happens in the app). If the endpoint accepts an API key, a paste field would do. If it needs the browser sign-in, the app needs that flow's protocol too, which is also undocumented.
3. **Not acceptable:** running `muse usage` as a subprocess or reading the CLI's stored credentials. That relies on another tool's login, which the project rules forbid.

## Ways to find the endpoint (needs the owner's go-ahead)

- Install the `muse` CLI into an isolated folder (`curl -fsSL https://dev.meta.ai/install.sh | bash` is the documented installer; its script and the binary would be read before running), sign in with the owner's test Meta AI account *by the owner*, and watch what `muse usage` sends through a local intercepting proxy. Nothing the CLI stores would be read by the app.
- Static look at the downloaded binary for URLs.

## Sources

- <https://dev.meta.ai/products/muse-code/>
- <https://dev.meta.ai/docs/muse-code/>
- <https://dev.meta.ai/docs/muse-code/subscriptions>
- <https://dev.meta.ai/docs/muse-code/auth>
- <https://dev.meta.ai/docs/muse-code/changelog>
- <https://dev.meta.ai/docs/pricing-rate-limits>
- <https://meta-models.github.io/muse-code-sdk/1.4/>
- <https://www.subscriptioninsider.com/blog/meta-adds-monthly-plans-as-muse-code-exits-beta>
