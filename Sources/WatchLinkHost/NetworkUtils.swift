import Foundation

enum NetworkUtils {
    static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(decoding: UnsafeRawBufferPointer(
                    start: interface.ifa_name,
                    count: strlen(interface.ifa_name)
                ), as: UTF8.self)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST
                    )
                    let length = hostname.firstIndex(of: 0) ?? hostname.count
                    address = hostname.prefix(length).withUnsafeBufferPointer {
                        String(decoding: $0.lazy.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    }
                }
            }
        }

        return address
    }
}
