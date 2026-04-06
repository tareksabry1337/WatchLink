public enum WatchLinkError: Error, Sendable {
    case noReachableTransport
    case sendFailed(String)
    case serverStartFailed(String)
    case queryTimedOut
}
