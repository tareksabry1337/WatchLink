import SwiftUI

@main
struct PingPongPhoneApp: App {
    @StateObject private var viewModel = PhoneViewModel()

    var body: some Scene {
        WindowGroup {
            PhoneContentView(viewModel: viewModel)
                .task { await viewModel.start() }
        }
    }
}
