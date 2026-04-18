/// Errors thrown by WatchLink send, reply, and host lifecycle calls.
public enum WatchLinkError: Error, Sendable {
    /// No transport is currently reachable and the message could not be queued.
    case noReachableTransport
    /// A transport rejected the frame; the associated string is the underlying description.
    case sendFailed(String)
    /// The host HTTP server failed to bind or start.
    case serverStartFailed(String)
    /// An awaited request-response exceeded its timeout before a reply arrived.
    case requestTimedOut
}
