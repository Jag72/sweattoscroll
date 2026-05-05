// ExtensionRequestView.swift
// PRD §5C — "free time is up" reflection modal with countdown timer + +15 min grant.

import SwiftUI

struct ExtensionRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reset = DailyResetManager.shared

    @State private var reason          = ""
    @State private var remainingSeconds: TimeInterval = 0
    @State private var timerTick       = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var granted         = false

    private var canContinue: Bool {
        reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    private var countdownText: String {
        let total = Int(remainingSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {

                // Countdown badge
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text(remainingSeconds > 0 ? countdownText : "0:00")
                            .font(.system(size: 48, weight: .black, design: .monospaced))
                            .foregroundColor(remainingSeconds > 0 ? .electricOrange : .rose)
                        Text("free time remaining")
                            .font(.capsLabel(12))
                            .foregroundColor(.muted)
                            .textCase(.uppercase)
                            .tracking(1)
                    }
                    Spacer()
                }
                .padding(.top, 8)

                Divider()

                Text("Your free time is up!")
                    .font(.title2.bold())
                    .foregroundColor(.ink)

                Text("Why do you want more time? Be honest with yourself.")
                    .font(.subheadline)
                    .foregroundColor(.muted)

                TextEditor(text: $reason)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if granted {
                    Label("15 minutes granted!", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.emeraldGreen)
                        .font(.bodyMedium(15))
                        .transition(.opacity)
                }

                Button {
                    reset.grantExtension(minutes: 15)
                    withAnimation { granted = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                } label: {
                    Text("Get 15 more minutes")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.electricOrange)
                .disabled(!canContinue || granted)

                Spacer()
            }
            .padding()
            .navigationTitle("Extra time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                remainingSeconds = reset.freeWindowRemainingSeconds
            }
            .onReceive(timerTick) { _ in
                remainingSeconds = max(0, reset.freeWindowRemainingSeconds)
            }
        }
    }
}
