# Refreshing

The app refreshes saved accounts through their provider APIs. A successful response updates that account's dashboard and menu-bar metrics and is cached so the last known values can appear at launch.

Provider requests run independently. A failure is shown for the affected account while its last successful values remain visible. A later refresh retries the request; use **Refresh Now** to request fresh values immediately.

Refreshes do not scan local files, combine usage history, or calculate spend from external pricing.
