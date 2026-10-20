# Privacy

OpenUsage Light only tracks accounts that a user adds in the app. Account labels and provider kinds are stored in the app's preferences; OAuth tokens and API keys are stored in the app's own Keychain service.

The app does not discover credentials or accounts from other tools and does not read their files, Keychain items, SQLite databases, or environment variables. It does not scan local usage logs or upload local usage history.

For each saved account, the app sends its credential to that provider's usage API to request account metrics. Credentials are not included in app logs.
