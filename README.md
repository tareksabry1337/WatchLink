# WatchLink

Reliable real-time messaging between Apple Watch and phone. Dual-transport (HTTP + WatchConnectivity). Cross-platform capable.

## Installation

```
https://github.com/tareksabry1337/WatchLink.git
```

iOS 13+ / watchOS 7+. Swift 6. No external dependencies.

## Modules

- **WatchLinkCore**: Message definitions. Import this in shared code where you define your message types.
- **WatchLink**: Watch-side client. BLE discovery, HTTP transport, SSE, connection management. Import on watchOS.
- **WatchLinkHost**: Phone-side host. HTTP server (Network.framework), BLE advertiser, SSE push. Import on iOS.

## Quick start

Define a message, conform to the protocol, and send it:

```swift
struct HeartRate: WatchLinkMessage {
    let bpm: Int
}
```

Watch side:

```swift
let link = WatchLink { config in
    config.transports = [.watchConnectivity, .http]
    config.bleServiceUUID = yourServiceUUID
    config.bleIPCharacteristicUUID = yourIPCharUUID
    config.httpPort = 8188
}

await link.connect()
try link.send(HeartRate(bpm: 72))
```

Phone side:

```swift
let host = WatchLinkHost { config in
    config.transports = [.watchConnectivity, .http]
    config.bleServiceUUID = yourServiceUUID
    config.bleIPCharacteristicUUID = yourIPCharUUID
    config.httpPort = 8188
}

try await host.start()

for await hr in host.messages(HeartRate.self) {
    print("Heart rate: \(hr.value.bpm)")
}
```

Request-response:

```swift
struct TimeRequest: WatchLinkMessage {
    typealias Response = TimeResponse
}

struct TimeResponse: WatchLinkMessage {
    let timestamp: Date
    let label: String
}

// Watch asks
let response = try await link.send(TimeRequest())

// Phone answers
for await request in host.messages(TimeRequest.self) {
    try await host.reply(
        with: TimeResponse(timestamp: Date(), label: "Phone clock"),
        to: request
    )
}
```

## How it works

The phone runs an HTTP server on the local network and advertises its IP over BLE. The Watch discovers it, connects over HTTP, and receives push via SSE. WatchConnectivity runs as a parallel transport. Every message is acked by the receiving device and retried until confirmed. Duplicates are caught by frame ID.

For the full story behind WatchLink, read the blog post: [WatchConnectivity was failing 40% of the time, so I stopped using it](https://tarek-builds.mataroa.blog/p/watchconnectivity-was-failing-40-of-the-time-so-i-stopped-using-it/)

## Things you should know

- Real-time delivery requires both apps to be active. Same as `sendMessageData`. WatchLink didn't add this constraint.
- Messages are never lost. Undelivered messages queue and flush when the connection re-establishes.
- This fixes the real-time path (`sendMessageData`). It does not replace `transferUserInfo` or `updateApplicationContext`.
- Cross-platform (Android, custom devices) is possible because the protocol is just HTTP + BLE. The v1 release is Swift only, so you'd need to write the host side yourself for now. Android and other platforms are planned. Contributions welcome.
- The HTTP server suspends when the phone backgrounds. On iOS, WatchConnectivity covers this. On Android, plan accordingly.

## Example app

`Examples/PingPongApp` has a full working app with ping/pong, heart rate streaming, request-response, and diagnostics.

## Credits

Built by [Tarek Sabry](https://github.com/tareksabry1337).

Special thanks to [Ahmed Hassan](https://github.com/ahmdmhasn) for reviewing the open-source release and contributing architectural improvements.

## License

MIT. See [LICENSE](LICENSE).
