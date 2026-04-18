# Contributing to WatchLink

Thanks for your interest. This is a small, focused library. PRs welcome.

## Development

Clone and open in Xcode:

```
git clone https://github.com/tareksabry1337/WatchLink.git
cd WatchLink
open Package.swift
```

## Running tests

Tests must run via `xcodebuild` on an iOS Simulator — `swift test` will not work because `WatchLink` and `WatchLinkHost` import `WatchConnectivity`.

```
xcodebuild test \
  -scheme WatchLink-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

Substitute the simulator name with whatever is installed locally (e.g. `iPhone 17` on newer Xcode).

## Device testing

Some behaviors (SSE on watchOS, BLE IP discovery, WC reachability) only reproduce on real hardware. `Examples/PingPongApp` is the reference harness — install on a paired iPhone + Apple Watch before submitting any transport-layer change.

## Pull requests

- Keep PRs focused. One concern per PR.
- Include a test for new behavior. All 123 existing tests must stay green.
- Match the existing code style (Swift 6 strict concurrency, actors over locks, `Sendable` everywhere, zero external dependencies).
- Prefer editing existing files over adding new abstractions.

## Reporting bugs

Open an issue with:
- iOS + watchOS versions
- Device models (simulator is fine for non-transport bugs)
- Transport configuration (`watchConnectivity`, `http`, or both)
- Reproduction steps
- Relevant log output (`WatchLinkLogger.osLog` emits under the `Transport` category)

## License

By contributing, you agree your contributions will be licensed under the MIT License.
