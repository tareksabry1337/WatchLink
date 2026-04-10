import os

public struct WatchLinkLogger: Sendable {
    private let minimumLevel: LogLevel
    private let handler: @Sendable (LogLevel, String) -> Void

    public init(
        minimumLevel: LogLevel = .debug,
        handler: @escaping @Sendable (LogLevel, String) -> Void
    ) {
        self.minimumLevel = minimumLevel
        self.handler = handler
    }

    public func debug(_ message: @autoclosure () -> String) {
        guard minimumLevel <= .debug else { return }
        handler(.debug, message())
    }

    public func info(_ message: @autoclosure () -> String) {
        guard minimumLevel <= .info else { return }
        handler(.info, message())
    }

    public func warning(_ message: @autoclosure () -> String) {
        guard minimumLevel <= .warning else { return }
        handler(.warning, message())
    }

    public func error(_ message: @autoclosure () -> String) {
        guard minimumLevel <= .error else { return }
        handler(.error, message())
    }

    public static let osLog = WatchLinkLogger { level, message in
        if #available(iOS 14.0, watchOS 7.0, *) {
            let logger = os.Logger(subsystem: "WatchLink", category: "Transport")
            switch level {
            case .debug: logger.debug("\(message)")
            case .info: logger.info("\(message)")
            case .warning: logger.warning("\(message)")
            case .error: logger.error("\(message)")
            case .none: break
            }
        } else {
            os_log("%{public}@", message)
        }
    }

    public static let none = WatchLinkLogger(minimumLevel: .none) { _, _ in }
}
