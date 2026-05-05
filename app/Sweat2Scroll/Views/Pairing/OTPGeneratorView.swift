// OTPGeneratorView.swift — PRD §6B (partner generates time-bounded OTP)

import SwiftUI

struct OTPGeneratorView: View {
    /// Duration options the partner can choose (minutes).
    private let durationOptions = [15, 30, 60]
    @State private var selectedDuration = 30
    @State private var code: String      = ""
    @State private var expiresAt: Date?
    @State private var remainingSeconds: TimeInterval = 0
    @State private var timerTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var copied = false

    private var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() >= exp
    }

    private var countdownText: String {
        guard !isExpired else { return "Expired" }
        let total = Int(remainingSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d remaining", m, s)
    }

    var body: some View {
        VStack(spacing: 24) {

            Text("Generate Unlock Code")
                .font(.display(22))
                .foregroundColor(.ink)

            Text("Choose how long the code is valid, then share it with the user.")
                .font(.bodyMedium(14))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)

            // Duration picker
            Picker("Duration", selection: $selectedDuration) {
                ForEach(durationOptions, id: \.self) { min in
                    Text("\(min) min").tag(min)
                }
            }
            .pickerStyle(.segmented)

            // OTP display
            if code.isEmpty {
                Button {
                    generateCode()
                } label: {
                    Text("Generate Code")
                        .font(.bodyMedium(17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.electricOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                GlassCard(padding: 20, cornerRadius: 20) {
                    VStack(spacing: 12) {
                        Text(formattedCode(code))
                            .font(.system(size: 48, weight: .black, design: .monospaced))
                            .foregroundColor(isExpired ? .muted : .ink)
                            .tracking(8)

                        Text(isExpired ? "Expired" : countdownText)
                            .font(.capsLabel(13))
                            .foregroundColor(isExpired ? .rose : .emeraldGreen)
                            .textCase(.uppercase)
                            .tracking(1)

                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = code
                                withAnimation { copied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { copied = false }
                                }
                            } label: {
                                Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.bodyMedium(14))
                            }
                            .buttonStyle(.bordered)
                            .tint(copied ? .emeraldGreen : .deepTeal)

                            Button {
                                generateCode()
                            } label: {
                                Label("New code", systemImage: "arrow.clockwise")
                                    .font(.bodyMedium(14))
                            }
                            .buttonStyle(.bordered)
                            .tint(.electricOrange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text("Note: Push notification to the user will be added in a future update.")
                .font(.caption)
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(24)
        .background(Color.paper.ignoresSafeArea())
        .onReceive(timerTick) { _ in
            guard let exp = expiresAt else { return }
            remainingSeconds = max(0, exp.timeIntervalSinceNow)
        }
    }

    // MARK: - Helpers

    private func generateCode() {
        // 6-digit numeric OTP — per PRD §6B, "1234" accepted in dev for OTPRequestView
        #if DEBUG
        code = "1234" + String(format: "%02d", Int.random(in: 10...99))
        #else
        code = String(format: "%06d", Int.random(in: 100000...999999))
        #endif
        let duration = TimeInterval(selectedDuration * 60)
        expiresAt        = Date().addingTimeInterval(duration)
        remainingSeconds = duration
        copied           = false
    }

    private func formattedCode(_ raw: String) -> String {
        // Insert a space after 3 chars for readability: "123 456"
        guard raw.count == 6 else { return raw }
        let idx = raw.index(raw.startIndex, offsetBy: 3)
        return String(raw[..<idx]) + " " + String(raw[idx...])
    }
}

#Preview {
    OTPGeneratorView()
}
