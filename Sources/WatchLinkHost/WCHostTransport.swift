import Foundation
import WatchConnectivity
import WatchLinkCore

package actor WCHostTransport: Transport {
    private let session: any WCSessionProtocol
    private var incomingContinuation: AsyncStream<IncomingMessage>.Continuation?
    private var reachabilityContinuation: AsyncStream<Bool>.Continuation?

    package var isReachable: Bool {
        session.isActivatedAndReachable
    }

    package var reachabilityChanges: AsyncStream<Bool> {
        AsyncStream { continuation in
            reachabilityContinuation = continuation
        }
    }

    package init(session: any WCSessionProtocol) {
        self.session = session
    }

    package func start() async {
        session.activate()
    }

    package func stop() async {
        incomingContinuation?.finish()
        incomingContinuation = nil
        reachabilityContinuation?.finish()
        reachabilityContinuation = nil
    }

    package func send(_ data: Data) async throws {
        guard isReachable else {
            throw WatchLinkError.sendFailed("WCSession not reachable")
        }

        session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    package func incoming() -> AsyncStream<IncomingMessage> {
        AsyncStream { continuation in
            incomingContinuation = continuation
        }
    }

    func handleIncoming(_ data: Data) {
        incomingContinuation?.yield(IncomingMessage(data: data))
    }

    func handleReachabilityChanged(_ reachable: Bool) {
        reachabilityContinuation?.yield(reachable)
    }
}

extension WCSession: WCSessionProtocol {
    package var isActivatedAndReachable: Bool {
        activationState == .activated && isReachable
    }
}

public final class WCHostSessionBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    private weak var transport: WCHostTransport?

    package init(transport: WCHostTransport, session: WCSession = .default) {
        self.transport = transport
        super.init()
        session.delegate = self
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { [weak transport] in
            await transport?.handleReachabilityChanged(reachable)
        }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { [weak transport] in
            await transport?.handleReachabilityChanged(reachable)
        }
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { [weak transport] in
            await transport?.handleIncoming(messageData)
        }
    }
}
