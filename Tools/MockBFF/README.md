# Mock BFF

A dependency-free Node server that implements [docs/BFF_CONTRACT.md](../../docs/BFF_CONTRACT.md)
with sample data, for running the app before the real backend exists.

```sh
cd Tools/MockBFF
npm start        # http://127.0.0.1:8787
npm test         # contract tests
```

The app only talks to a bare HTTPS host name (`AppConfiguration.isValidHost`: no scheme, port or
path), and App Transport Security stays on. To run the app against the mock, put it behind an
HTTPS tunnel or a local TLS proxy that gives it a host name, and set that name as
`BACKEND_HOST` in `Config/Secrets.xcconfig`. Without a host the app uses its built-in fallbacks.

Bearer tokens that select a scenario: `expired` (401), `throttled` (429), `empty` (no orders).
Order `1001` has a key, `1002` is pending (202), `1003` was shipped, `9999` belongs to someone else (403).
