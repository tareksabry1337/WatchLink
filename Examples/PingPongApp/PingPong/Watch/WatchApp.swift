import SwiftUI

@main
struct PingPongWatchApp: App {
    @StateObject private var viewModel = WatchViewModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView(viewModel: viewModel)
                .task { await viewModel.start() }
        }
    }
}
