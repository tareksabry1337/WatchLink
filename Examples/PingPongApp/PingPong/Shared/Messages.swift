import Foundation
import WatchLinkCore

struct Ping: WatchLinkMessage {
    static let channel: Channel = "ping"
    let count: Int
    let sentAt: Date
}

struct Pong: WatchLinkMessage {
    static let channel: Channel = "pong"
    let count: Int
    let roundTripMs: Int
}

struct HeartRate: WatchLinkMessage {
    static let channel: Channel = "heartRate"
    let bpm: Int
}
