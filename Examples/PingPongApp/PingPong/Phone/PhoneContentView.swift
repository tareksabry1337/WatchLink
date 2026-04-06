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

                Section("Diagnostics") {
                    HStack {
                        Label("WC", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Circle()
                            .fill(viewModel.diag.wcReachable ? .green : .red)
                            .frame(width: 10, height: 10)
                    }
                    HStack {
                        Label("HTTP", systemImage: "network")
                        Spacer()
                        Circle()
                            .fill(viewModel.diag.httpReachable ? .green : .red)
                            .frame(width: 10, height: 10)
                    }
                    HStack {
                        Text("SSE Clients")
                        Spacer()
                        Text("\(viewModel.diag.sseClientCount)")
                            .font(.body.monospacedDigit())
                    }
                    HStack {
                        Text("Pending Queue")
                        Spacer()
                        Text("\(viewModel.diag.pendingQueueCount)")
                            .font(.body.monospacedDigit())
                    }
                    HStack {
                        Text("Seen IDs")
                        Spacer()
                        Text("\(viewModel.diag.seenIDsCount)")
                            .font(.body.monospacedDigit())
                    }
                    HStack {
                        Text("Unacked")
                        Spacer()
                        Text("\(viewModel.diag.unackedCount)")
                            .font(.body.monospacedDigit())
                    }
                }

                Section("IP Discovery") {
                    HStack {
                        Text("NWConnection")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.nwConnectionIP)
                            .font(.body.monospaced())
                    }
                    HStack {
                        Text("getifaddrs")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.getifaddrsIP)
                            .font(.body.monospaced())
                    }
                    Button("Detect IP") {
                        Task { await viewModel.detectIP() }
                    }
                }

                Section("Log") {
                    if viewModel.entries.isEmpty {
                        Text("Waiting...")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.entries.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("WatchLink Host")
        }
    }
}
