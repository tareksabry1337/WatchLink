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

                HStack(spacing: 8) {
                    Button("Ping") {
                        Task { await viewModel.sendPing() }
                    }
                    .font(.caption)

                    Button("HR") {
                        Task { await viewModel.sendHeartRate() }
                    }
                    .font(.caption)

                    Button("Time?") {
                        Task { await viewModel.queryTime() }
                    }
                    .font(.caption)
                }

                if viewModel.phoneTime != "—" {
                    Text("Phone: \(viewModel.phoneTime)")
                        .font(.caption2.monospaced())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnostics")
                        .font(.caption2.bold())
                    HStack {
                        Text("WC")
                            .font(.system(size: 9))
                        Circle()
                            .fill(viewModel.diag.wcReachable ? .green : .red)
                            .frame(width: 6, height: 6)
                        Text("HTTP")
                            .font(.system(size: 9))
                        Circle()
                            .fill(viewModel.diag.httpReachable ? .green : .red)
                            .frame(width: 6, height: 6)
                    }
                    Text("IP: \(viewModel.diag.serverIP ?? "—")")
                        .font(.system(size: 9).monospaced())
                    Text("Queue: \(viewModel.diag.pendingQueueCount) | Unacked: \(viewModel.diag.unackedCount)")
                        .font(.system(size: 9).monospaced())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                ForEach(Array(viewModel.entries.enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
        }
    }
}
