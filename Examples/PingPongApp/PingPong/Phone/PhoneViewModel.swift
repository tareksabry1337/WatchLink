import Foundation
import Network
import WatchLinkHost
import WatchLinkCore

@Observable
@MainActor
final class PhoneViewModel {
    private(set) var status = "Starting..."
    private(set) var pingCount = 0
    private(set) var lastPingValue = 0
    private(set) var heartRateBPM = 0
    private(set) var entries: [String] = []
    private(set) var nwConnectionIP = "—"
    private(set) var getifaddrsIP = "—"
    private(set) var diag = WatchLinkDiagnostics()

    @ObservationIgnored
    private lazy var host: WatchLinkHost = WatchLinkHost { [weak self] config in
        config.transports = [.watchConnectivity, .http]
        config.bleServiceUUID = BLEConstants.serviceUUID
        config.bleIPCharacteristicUUID = BLEConstants.ipCharacteristicUUID
        config.httpPort = 8188
        config.logger = WatchLinkLogger { level, message in
            Task { @MainActor in
                self?.addEntry("[\(level)] \(message)")
            }
        }
    }

    func start() async {
        addEntry("Starting host...")
        do {
            try await host.start()
            status = "Listening"
            addEntry("Host started")
        } catch {
            status = "Failed: \(error)"
            addEntry("Start failed: \(error)")
            return
        }

        async let pings: Void = listenForPings()
        async let heartRates: Void = listenForHeartRates()
        async let diagLoop: Void = refreshDiagnostics()
        _ = await (pings, heartRates, diagLoop)
    }

    private func listenForPings() async {
        for await ping in await host.messages(Ping.self) {
            pingCount += 1
            lastPingValue = ping.value.count
            addEntry("Ping #\(ping.value.count)")

            let roundTrip = Int(Date().timeIntervalSince(ping.value.sentAt) * 1000)
            do {
                try await host.reply(to: ping, with: Pong(count: ping.value.count, roundTripMs: roundTrip))
                addEntry("Pong #\(ping.value.count) (\(roundTrip)ms)")
            } catch {
                addEntry("Pong failed: \(error)")
            }
        }
    }

    private func listenForHeartRates() async {
        for await hr in await host.messages(HeartRate.self) {
            heartRateBPM = hr.value.bpm
            addEntry("HR: \(hr.value.bpm) bpm")
        }
    }

    func sendToWatch() async {
        let pong = Pong(count: pingCount + 1, roundTripMs: 0)
        do {
            try await host.send(pong)
            addEntry("Sent pong to watch")
        } catch {
            addEntry("Send to watch failed: \(error)")
        }
    }

    private func refreshDiagnostics() async {
        while true {
            diag = await host.diagnostics()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func detectIP() async {
        nwConnectionIP = "Detecting..."
        getifaddrsIP = "Detecting..."

        nwConnectionIP = await detectViaNWConnection()
        getifaddrsIP = detectViaGetifaddrs()
    }

    private func detectViaNWConnection() async -> String {
        let connection = NWConnection(host: "1.1.1.1", port: 53, using: .udp)

        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let local = connection.currentPath?.localEndpoint,
                       case .hostPort(let host, _) = local {
                        continuation.resume(returning: "\(host)")
                    } else {
                        continuation.resume(returning: "No endpoint")
                    }
                    connection.cancel()
                case .failed(let error):
                    continuation.resume(returning: "Failed: \(error)")
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private nonisolated func detectViaGetifaddrs() -> String {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return "Failed" }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }

        return address ?? "Not found"
    }

    func addEntry(_ message: String) {
        entries.insert(message, at: 0)
        if entries.count > 100 { entries.removeLast() }
    }
}
