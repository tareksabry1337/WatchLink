#if os(iOS)
import Foundation
import Network

enum NetworkUtils {
    static func localIPAddress() async -> String? {
        if let ip = await detectViaNWConnection() {
            return ip
        }
        return detectViaGetifaddrs()
    }

    private static func detectViaNWConnection() async -> String? {
        let connection = NWConnection(host: "1.1.1.1", port: 53, using: .udp)

        let states = AsyncStream<NWConnection.State> { continuation in
            connection.stateUpdateHandler = { state in
                continuation.yield(state)
                if case .ready = state { continuation.finish() }
                if case .failed = state { continuation.finish() }
                if case .cancelled = state { continuation.finish() }
            }
            connection.start(queue: .global())
        }

        var ip: String?
        for await state in states {
            if case .ready = state,
               let local = connection.currentPath?.localEndpoint,
               case .hostPort(let host, _) = local {
                ip = "\(host)"
            }
            break
        }

        connection.cancel()
        return ip
    }

    private static func detectViaGetifaddrs() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(validatingCString: interface.ifa_name) ?? ""
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST
                    )
                    address = String(validatingCString: &hostname) ?? ""
                }
            }
        }

        return address
    }
}
#endif
