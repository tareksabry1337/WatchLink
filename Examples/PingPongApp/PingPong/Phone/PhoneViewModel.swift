import Foundation
import WatchLinkHost
import WatchLinkCore

@Observable
@MainActor
final class PhoneViewModel {
    private(set) var status = "Starting..."
    private(set) var pingCount = 0
    private(set) var lastPingValue = 0
    private(set) var heartRateBPM = 0
    private(set) var log: [String] = []

    private let host = WatchLinkHost { config in
        config.transports = [.watchConnectivity, .http]
        config.bleServiceUUID = BLEConstants.serviceUUID
        config.bleIPCharacteristicUUID = BLEConstants.ipCharacteristicUUID
        config.httpPort = 8188
    }

    func start() async {
        do {
            try await host.start()
            status = "Listening"
            addLog("Host started")
        } catch {
            status = "Failed: \(error)"
            addLog("Start failed: \(error)")
            return
        }

        async let pings: Void = listenForPings()
        async let heartRates: Void = listenForHeartRates()
        _ = await (pings, heartRates)
    }

    private func listenForPings() async {
        for await ping in await host.messages(Ping.self) {
            pingCount += 1
            lastPingValue = ping.count
            addLog("Ping #\(ping.count)")

            let roundTrip = Int(Date().timeIntervalSince(ping.sentAt) * 1000)
            do {
                try await host.send(Pong(count: ping.count, roundTripMs: roundTrip))
                addLog("Pong #\(ping.count) (\(roundTrip)ms)")
            } catch {
                addLog("Pong failed: \(error)")
            }
        }
    }

    private func listenForHeartRates() async {
        for await hr in await host.messages(HeartRate.self) {
            heartRateBPM = hr.bpm
            addLog("HR: \(hr.bpm) bpm")
        }
    }

    func sendToWatch() async {
        let pong = Pong(count: pingCount + 1, roundTripMs: 0)
        do {
            try await host.send(pong)
            addLog("Sent pong to watch")
        } catch {
            addLog("Send to watch failed: \(error)")
        }
    }

    private func addLog(_ message: String) {
        log.insert(message, at: 0)
        if log.count > 50 { log.removeLast() }
    }
}
