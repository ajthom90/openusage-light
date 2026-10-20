# Debugging

Run the focused SwiftPM checks from the repository root:

```sh
swift build
swift test
```

To build and launch the local menu-bar app:

```sh
./script/build_and_run.sh verify
```

Provider sign-in and refresh use the account credential stored by the app. Never add a real token or API key to a test fixture, log, or command line. Tests should use stub HTTP responses and in-memory stores.
