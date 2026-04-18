#if os(iOS)
import Foundation
import WatchLinkCore

package enum HTTPStatus: Int, Sendable, Equatable {
    case ok = 200
    case notFound = 404

    package var text: String {
        switch self {
        case .ok: "OK"
        case .notFound: "Not Found"
        }
    }
}

package enum HTTPEffect: Sendable, Equatable {
    case yieldIncoming(Data)
    case holdConnection(frameID: String)
    case resolveReply(frameID: String, Data)
    case startSSE
    case respond(HTTPStatus, body: Data?)
}

package enum HTTPRequestRouter {
    package struct ParsedRequest: Equatable, Sendable {
        package let route: HTTPRoute?
        package let headers: [String: String]
        package let body: Data?
    }

    package static func parse(_ data: Data) -> ParsedRequest {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let lines = raw.components(separatedBy: "\r\n")
        let requestLine = lines.first?.components(separatedBy: " ") ?? []
        let method = HTTPMethod(rawValue: requestLine.count > 0 ? requestLine[0] : "")
        let path = requestLine.count > 1 ? requestLine[1] : ""
        let route = method.flatMap { HTTPRoute(method: $0, path: path) }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        var body: Data?
        if let sep = raw.range(of: "\r\n\r\n") {
            let bodyString = String(raw[sep.upperBound...])
            if !bodyString.isEmpty {
                body = Data(bodyString.utf8)
            }
        }

        return ParsedRequest(route: route, headers: headers, body: body)
    }

    package static func parseContentLength(_ raw: String) -> Int {
        for line in raw.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    package static func effects(for request: ParsedRequest) -> [HTTPEffect] {
        switch request.route {
        case .message:
            if let body = request.body {
                return [.yieldIncoming(body), .respond(.ok, body: nil)]
            }
            return [.respond(.ok, body: nil)]

        case .request:
            guard let body = request.body,
                  let frame = try? JSONDecoder().decode(Frame.self, from: body) else {
                return [.respond(.notFound, body: nil)]
            }
            return [.yieldIncoming(body), .holdConnection(frameID: frame.id)]

        case .reply:
            if let frameID = request.headers["x-frame-id"], let body = request.body {
                return [.resolveReply(frameID: frameID, body), .respond(.ok, body: nil)]
            }
            return [.respond(.ok, body: nil)]

        case .events:
            return [.startSSE]

        case .health:
            return [.respond(.ok, body: nil)]

        case nil:
            return [.respond(.notFound, body: nil)]
        }
    }
}
#endif
