import Foundation

package struct IncomingMessage: Sendable {
    package let data: Data

    package init(data: Data) {
        self.data = data
    }
}
