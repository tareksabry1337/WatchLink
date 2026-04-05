import Testing
import Foundation
@testable import WatchLinkCore

@Suite("Logger")
struct LoggerTests {

    @Test("debug level invokes handler with debug")
    func debugLevel() {
        let holder = LogHolder()
        let logger = WatchLinkLogger { level, message in
            holder.record(level, message)
        }
        logger.debug("test debug")
        #expect(holder.lastLevel == .debug)
        #expect(holder.lastMessage == "test debug")
    }

    @Test("info level invokes handler with info")
    func infoLevel() {
        let holder = LogHolder()
        let logger = WatchLinkLogger { level, message in
            holder.record(level, message)
        }
        logger.info("test info")
        #expect(holder.lastLevel == .info)
        #expect(holder.lastMessage == "test info")
    }

    @Test("warning level invokes handler with warning")
    func warningLevel() {
        let holder = LogHolder()
        let logger = WatchLinkLogger { level, message in
            holder.record(level, message)
        }
        logger.warning("test warning")
        #expect(holder.lastLevel == .warning)
        #expect(holder.lastMessage == "test warning")
    }

    @Test("error level invokes handler with error")
    func errorLevel() {
        let holder = LogHolder()
        let logger = WatchLinkLogger { level, message in
            holder.record(level, message)
        }
        logger.error("test error")
        #expect(holder.lastLevel == .error)
        #expect(holder.lastMessage == "test error")
    }

    @Test("none logger produces no output")
    func noneLogger() {
        let holder = LogHolder()
        let original = WatchLinkLogger.none
        original.debug("should not appear")
        original.error("should not appear")
        #expect(holder.lastLevel == nil)
    }

    @Test("log levels are ordered correctly")
    func levelOrdering() {
        #expect(LogLevel.debug < .info)
        #expect(LogLevel.info < .warning)
        #expect(LogLevel.warning < .error)
        #expect(LogLevel.error < .none)
    }

}

private class LogHolder: @unchecked Sendable {
    var lastLevel: LogLevel?
    var lastMessage: String?

    func record(_ level: LogLevel, _ message: String) {
        lastLevel = level
        lastMessage = message
    }
}
