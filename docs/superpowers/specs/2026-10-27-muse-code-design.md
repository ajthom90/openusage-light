# Muse Code usage tracking: findings and open questions

Status: **blocked on a documented usage source; nothing built.** Findings are from Meta's public pages read on 2026-10-27.

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

## What is not documented (the blocker)

Neither the product page (`dev.meta.ai/products/muse-code/`) nor the docs page (`dev.meta.ai/docs/muse-code/`) names any command, endpoint, or dashboard that reports remaining usage, limits, or reset times. `muse serve`, `muse schema`, and the `@muse-code/sdk` package are described without any usage data. The docs navigation lists a **pricing and rate limits** page and an **authentication and billing** page that I have **not** read; they are the next place to look.

## Fit with the project rules (AGENTS.md)

- Usage must come from a provider API the app calls with a sign-in the user performs in the app.
- The app must not read the Muse Code CLI's saved credentials, files, or environment (`META_API_KEY` included), and must not scan its logs.
- No estimates: counting prompts and dividing by an allowance such as "10-50 prompts" would be an estimate, so a usage meter needs Meta to report used and limit.

## Open questions

1. Do the rate-limits and billing pages document a usage endpoint, and what auth does it take (an API key the user pastes in the app, or browser sign-in with a redirect the app can host)?
2. If Meta has no public usage endpoint, is it acceptable to show only the plan name and its stated allowance, with no used/remaining meter? (This would not be a usage tracker.)
3. Is it acceptable to look at what the CLI itself calls to learn a private endpoint? That would rely on an undocumented API that can change without notice.

## Sources

- <https://dev.meta.ai/products/muse-code/>
- <https://dev.meta.ai/docs/muse-code/>
- <https://www.subscriptioninsider.com/blog/meta-adds-monthly-plans-as-muse-code-exits-beta>
