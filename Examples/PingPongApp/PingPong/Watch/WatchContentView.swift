import SwiftUI

struct WatchContentView: View {
    let viewModel: WatchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Circle()
                        .fill(viewModel.connectionState == "connected" ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.connectionState)
                        .font(.caption2)
                }

                HStack(spacing: 16) {
                    VStack {
                        Text("\(viewModel.pongCount)")
                            .font(.title2.bold())
                        Text("pongs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack {
                        Text("\(viewModel.lastRoundTripMs)ms")
                            .font(.title2.bold())
                        Text("latency")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Send Ping") {
                    Task { await viewModel.sendPing() }
                }

                Button("Send HR") {
                    Task { await viewModel.sendHeartRate() }
                }

                Divider()

                ForEach(Array(viewModel.entries.enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
        }
    }
}
