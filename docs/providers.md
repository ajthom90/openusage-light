# Providers

Sign in to every provider from Settings → Accounts. OAuth credentials and API keys are saved in the app's own Keychain service.

## Claude

- Sign-in: `https://claude.ai/oauth/authorize`, `https://platform.claude.com/v1/oauth/token`
- Usage: `https://api.anthropic.com/api/oauth/profile`, `https://api.anthropic.com/api/oauth/usage`

## Codex

- Sign-in: `https://auth.openai.com/oauth/authorize`, `https://auth.openai.com/oauth/token`, `https://auth.openai.com/api/accounts/deviceauth/usercode`, `https://auth.openai.com/api/accounts/deviceauth/token`
- Usage: `https://chatgpt.com/backend-api/wham/usage`

## Cursor

- Sign-in: `https://cursor.com/loginDeepControl`, `https://api2.cursor.sh/auth/poll`, `https://api2.cursor.sh/oauth/token`
- Usage: `https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`, `https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus`, `https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo`, `https://api2.cursor.sh/aiserver.v1.DashboardService/GetCreditGrantsBalance`, `https://cursor.com/api/usage`, `https://cursor.com/api/usage-summary`, `https://cursor.com/api/auth/stripe`

## Antigravity

- Sign-in: `https://accounts.google.com/o/oauth2/v2/auth`, `https://oauth2.googleapis.com/token`, `https://www.googleapis.com/oauth2/v1/userinfo`
- Usage: `https://cloudcode-pa.googleapis.com` and `https://daily-cloudcode-pa.googleapis.com` with `/v1internal:fetchAvailableModels`, `/v1internal:loadCodeAssist`, `/v1internal:retrieveUserQuota`, and `/v1internal:retrieveUserQuotaSummary`

## Copilot

- Sign-in: `https://github.com/login/device/code`, `https://github.com/login/oauth/access_token`, `https://api.github.com/user`
- Usage: `https://api.github.com/copilot_internal/user`

## Grok

- Sign-in: `https://auth.x.ai/oauth2/device/code`, `https://auth.x.ai/oauth2/token`
- Usage: `https://cli-chat-proxy.grok.com/v1/settings`, `https://cli-chat-proxy.grok.com/v1/billing?format=credits`

## Ollama

- Sign-in: API key entered in Settings → Accounts
- Usage: `https://ollama.com/api/balance`, `https://ollama.com/api/me`

## OpenCode Go

- Sign-in: API key entered in Settings → Accounts
- Usage: `https://opencode.ai/zen/go/v1/usage`

## OpenRouter

- Sign-in: API key entered in Settings → Accounts
- Usage: `https://openrouter.ai/api/v1/credits`, `https://openrouter.ai/api/v1/key`

## Z.ai

- Sign-in: API key entered in Settings → Accounts
- Usage: `https://api.z.ai/api/biz/subscription/list`, `https://api.z.ai/api/monitor/usage/quota/limit`
