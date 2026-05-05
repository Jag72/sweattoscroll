// Views/Pairing/PairCodeGeneratorView.swift

import SwiftUI

struct PairCodeGeneratorView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var code: String = "------"
    @State private var expiresAt = Date().addingTimeInterval(600)
    @State private var now = Date()
    @State private var isGenerating = false
    @State private var paired = false
    @State private var pollTask: Task<Void, Never>?

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Share this code")
                    .font(.title2.bold())
                Text(code)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .tracking(6)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.electricOrange.opacity(0.12)))

                Text("Valid for \(remainingSeconds)s")
                    .font(.caption)
                    .foregroundColor(.muted)
                    .onReceive(timer) { now = $0 }

                Button("Regenerate") { Task { await generate() } }
                    .disabled(isGenerating)

                if paired {
                    Label("User paired successfully", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.emeraldGreen)
                }

                Spacer()
                Text("Ask them to open Sweat2Scroll → Enter pair code.")
                    .font(.footnote)
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Pair code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        pollTask?.cancel()
                        dismiss()
                    }
                }
            }
            .task {
                await generate()
                startPolling()
            }
            .onDisappear { pollTask?.cancel() }
        }
    }

    private var remainingSeconds: Int {
        max(0, Int(expiresAt.timeIntervalSince(now)))
    }

    private func generate() async {
        guard let mid = auth.currentAppleUserID else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let c = try await PairingService.shared.generateCode(forMonitorID: mid)
            code = c
            expiresAt = Date().addingTimeInterval(600)
        } catch {
            code = "ERROR"
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        guard let mid = auth.currentAppleUserID else { return }
        pollTask = Task {
            let ok = await PairingService.shared.pollForPairingConfirmation(monitorAppleUserID: mid)
            if ok {
                await auth.refreshAfterPairing()
                await MainActor.run { paired = true }
            }
        }
    }
}
