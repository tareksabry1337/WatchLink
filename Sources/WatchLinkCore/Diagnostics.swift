import Foundation

public struct WatchLinkDiagnostics: Sendable {
    public init() {}
    public var sseClientCount: Int = 0
    public var pendingQueueCount: Int = 0
    public var seenIDsCount: Int = 0
    public var unackedCount: Int = 0
    public var wcReachable: Bool = false
    public var httpReachable: Bool = false
    public var connectionState: ConnectionState = .disconnected
    public var lastHeartbeatAt: Date?
    public var serverIP: String?
    public var pendingConfirmationsCount: Int = 0
}
