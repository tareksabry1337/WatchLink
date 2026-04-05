import SwiftUI

struct PhoneContentView: View {
    let viewModel: PhoneViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(viewModel.status == "Listening" ? .green : .orange)
                            .frame(width: 12, height: 12)
                        Text(viewModel.status)
                            .font(.headline)
                    }
                }

                Section("Stats") {
                    HStack {
                        Label("Pings", systemImage: "arrow.down.circle")
                        Spacer()
                        Text("\(viewModel.pingCount)")
                            .font(.title2.bold().monospacedDigit())
                    }

                    HStack {
                        Label("Heart Rate", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                        Spacer()
                        Text(viewModel.heartRateBPM > 0 ? "\(viewModel.heartRateBPM) bpm" : "--")
                            .font(.title2.bold().monospacedDigit())
                    }
                }

                Section {
                    Button("Send Pong to Watch") {
                        Task { await viewModel.sendToWatch() }
                    }
                }

                Section("Log") {
                    if viewModel.log.isEmpty {
                        Text("Waiting for messages...")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.log.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("WatchLink Host")
        }
    }
}
