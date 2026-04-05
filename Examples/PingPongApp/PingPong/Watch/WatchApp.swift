import SwiftUI

@main
struct PingPongWatchApp: App {
    @State private var viewModel = WatchViewModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView(viewModel: viewModel)
                .task { await viewModel.start() }
        }
    }
}
