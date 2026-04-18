import Foundation

/// Snapshot of WatchLink's internal state, for debug UI and instrumentation.
///
/// Populate via `WatchLink.diagnostics()` / `WatchLinkHost.diagnostics()`.
public struct WatchLinkDiagnostics: Sendable {
    public init() {}
    /// Number of SSE clients currently subscribed (host only).
    public var sseClientCount: Int = 0
    /// Messages awaiting a reachable transport.
    public var pendingQueueCount: Int = 0
    /// Size of the frame-ID dedup set.
    public var seenIDsCount: Int = 0
    /// Messages sent but not yet acknowledged by the peer.
    public var unackedCount: Int = 0
    /// Whether the WatchConnectivity transport reports reachable.
    public var wcReachable: Bool = false
    /// Whether the HTTP/SSE transport reports reachable.
    public var httpReachable: Bool = false
    /// Most recent observed connection state.
    public var connectionState: ConnectionState = .disconnected
    /// Wall-clock time of the last incoming heartbeat.
    public var lastHeartbeatAt: Date?
    /// The phone's local IP as discovered via BLE (watch only).
    public var serverIP: String?
    /// Awaiting reply continuations tracked by frame ID.
    public var pendingConfirmationsCount: Int = 0
}
