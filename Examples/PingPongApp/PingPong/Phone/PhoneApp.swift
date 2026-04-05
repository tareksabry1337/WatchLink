import SwiftUI

@main
struct PingPongPhoneApp: App {
    @State private var viewModel = PhoneViewModel()

    var body: some Scene {
        WindowGroup {
            PhoneContentView(viewModel: viewModel)
                .task { await viewModel.start() }
        }
    }
}
