import Foundation
import WatchLinkCore

struct Ping: WatchLinkMessage {
    let count: Int
    let sentAt: Date
}

struct Pong: WatchLinkMessage {
    let count: Int
    let roundTripMs: Int
}

struct HeartRate: WatchLinkMessage {
    let bpm: Int
}

struct TimeRequest: WatchLinkMessage {
    typealias Response = TimeResponse
}

struct TimeResponse: WatchLinkMessage {
    let timestamp: Date
    let label: String
}
