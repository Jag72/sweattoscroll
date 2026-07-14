// Views/Pairing/EmergencyOverrideView.swift
// Partner emergency override using a 30-SECOND ROTATING TOTP.
//
//   Send   (controller / monitor) — shows a live 6-digit code derived from the
//          shared secret established at pairing. It rotates every 30 seconds; a
//          countdown ring shows how long the current code is valid. Nothing is
//          written to CloudKit — the code is verified locally against the same
//          shared secret on the other device.
//
//   Receive (controlled / user)   — type the code your partner reads you. We
//          validate it against the shared secret (±1 step tolerance so a code
//          read aloud at second 29 still works at second 31). On success the
//          blocked apps unlock for a FIXED 15 MINUTES, then re-shield.
//
// Tabs are gated by the local `PartnershipRole`:
//   controlled → Receive only · controller → Send only · mutual → both.

import SwiftUI

struct EmergencyOverrideView: View {
    @ObservedObject private var auth = AuthManager.shared
    @EnvironmentObject private var activityVM: ActivityViewModel
    @Environment(\.dismiss) private var dismiss

    /// Fixed unlock granted when a valid override code is redeemed.
    static let unlockMinutes = 15
    /// TOTP rotation period — must match `TOTPService.timeStepSeconds`.
    private let periodSeconds = Int(TOTPService.timeStepSeconds)

    @State private var mode: Mode = .receive
    @State private var receiveDigits: [String] = Array(repeating: "", count: 6)
    @FocusState private var receiveFocus: Int?
    @State private var receiveStatus: Status = .idle
    @State private var isSubmitting = false

    // Live TOTP (send side)
    @State private var liveCode: String = "------"
    @State private var secondsRemaining: Int = 30
    @State private var copied = false
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private enum Mode: String, CaseIterable, Identifiable {
        case receive, send
        var id: String { rawValue }
        var label: String { self == .receive ? "Receive code" : "Send code" }
    }

    private enum Status: Equatable {
        case idle, success(String), error(String)
    }

    // MARK: - Pairing / role state

    private var isPaired: Bool {
        (auth.cachedAccount?.isPaired ?? false) && TOTPService.hasSharedSecret
    }
    private var role: PartnershipRole { auth.cachedAccount?.partnershipRole ?? .mutual }
    private var partnerName: String {
        let n = auth.cachedAccount?.relationshipLabel ?? ""
        return n.isEmpty ? "Your partner" : n
    }
    private var availableModes: [Mode] {
        [role.canRedeemOverride ? Mode.receive : nil,
         role.canGrantOverride ? Mode.send : nil].compactMap { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    if availableModes.count > 1 {
                        Picker("Mode", selection: $mode) {
                            ForEach(availableModes) { m in Text(m.label).tag(m) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                    }

                    if !isPaired {
                        unpairedNotice
                    } else {
                        switch mode {
                        case .receive: receivePane
                        case .send:    sendPane
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Emergency override")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.electricOrange)
                }
            }
            .onAppear {
                mode = availableModes.first ?? .receive
                refreshLiveCode()
            }
            .onReceive(ticker) { _ in refreshLiveCode() }
        }
    }

    // MARK: - Unpaired

    private var unpairedNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 38)).foregroundColor(.muted.opacity(0.4))
            Text("Pair with a partner first")
                .font(.system(size: 17, weight: .bold)).foregroundColor(.ink)
            Text("Share a 6-digit pair code with your partner to set up a secure link. After that you can send and receive 30-second override codes here.")
                .font(.system(size: 13)).foregroundColor(.muted)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
        }
        .padding(.top, 40)
    }

    // MARK: - Send (live rotating TOTP)

    private var sendPane: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Read this code to \(partnerName)")
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.ink)
                Text("It changes every \(periodSeconds) seconds. When it expires, just read the new one.")
                    .font(.system(size: 12)).foregroundColor(.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }

            ZStack {
                Circle().stroke(Color.electricOrange.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(secondsRemaining) / CGFloat(periodSeconds))
                    .stroke(Color.electricOrange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: secondsRemaining)
                VStack(spacing: 4) {
                    Text(formattedCode(liveCode))
                        .font(.system(size: 34, weight: .black, design: .monospaced))
                        .tracking(4)
                        .foregroundColor(.ink)
                    Text("\(secondsRemaining)s")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(secondsRemaining <= 5 ? .rose : .emeraldGreen)
                }
            }
            .frame(width: 200, height: 200)

            Button {
                UIPasteboard.general.string = liveCode
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation { copied = false }
                }
            } label: {
                Label(copied ? "Copied!" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(copied ? .emeraldGreen : .deepTeal)

            Text("When \(partnerName) enters this code, their blocked apps unlock for \(Self.unlockMinutes) minutes.")
                .font(.system(size: 12)).foregroundColor(.muted)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
        }
    }

    // MARK: - Receive (validate → 15-min unlock)

    private var receivePane: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Enter the code from \(partnerName)")
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.ink)
                    .multilineTextAlignment(.center)
                Text("Codes are valid for \(periodSeconds) seconds — ask for a fresh one if it expires.")
                    .font(.system(size: 12)).foregroundColor(.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    TextField("", text: Binding(
                        get: { receiveDigits[i] },
                        set: { new in
                            let trimmed = String(new.filter(\.isNumber).prefix(1))
                            receiveDigits[i] = trimmed
                            if !trimmed.isEmpty, i < 5 { receiveFocus = i + 1 }
                            if receiveCode.count == 6 { submitReceived() }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .frame(width: 44, height: 56)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 2))
                    .focused($receiveFocus, equals: i)
                }
            }

            statusLabel

            Button(action: submitReceived) {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(.white) }
                    Text(isSubmitting ? "Checking…" : "Unlock for \(Self.unlockMinutes) min")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.electricOrange.opacity(receiveCode.count == 6 ? 1 : 0.4)))
            }
            .disabled(isSubmitting || receiveCode.count != 6)
            .padding(.horizontal, 20)
        }
        .onAppear { receiveFocus = 0 }
    }

    private var borderColor: Color {
        switch receiveStatus {
        case .success: return .emeraldGreen
        case .error:   return .rose
        default:       return .ringTrack
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch receiveStatus {
        case .idle: EmptyView()
        case .success(let m):
            Label(m, systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold)).foregroundColor(.emeraldGreen)
        case .error(let m):
            Label(m, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold)).foregroundColor(.rose)
        }
    }

    // MARK: - Actions

    private var receiveCode: String { receiveDigits.joined() }

    private func refreshLiveCode() {
        secondsRemaining = periodSeconds - Int(Date().timeIntervalSince1970) % periodSeconds
        guard role.canGrantOverride, TOTPService.hasSharedSecret else { return }
        if let code = try? TOTPService.generateCode() { liveCode = code }
    }

    private func submitReceived() {
        guard !isSubmitting, receiveCode.count == 6 else { return }
        isSubmitting = true
        receiveStatus = .idle
        let code = receiveCode
        Task {
            let valid = (try? TOTPService.validateCode(code)) ?? false
            await MainActor.run {
                isSubmitting = false
                if valid {
                    // FIXED 15-minute unlock, then auto re-shield.
                    activityVM.applyEmergencyOverride(
                        durationMinutes: Self.unlockMinutes,
                        grantedBy: partnerName,
                        reason: "Partner override")
                    receiveStatus = .success("Unlocked for \(Self.unlockMinutes) minutes")
                    HapticEngine.success()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        dismiss()
                    }
                } else {
                    receiveStatus = .error("Invalid or expired code. Ask for a fresh one.")
                    receiveDigits = Array(repeating: "", count: 6)
                    receiveFocus = 0
                    HapticEngine.error()
                }
            }
        }
    }

    private func formattedCode(_ raw: String) -> String {
        guard raw.count == 6 else { return raw }
        let idx = raw.index(raw.startIndex, offsetBy: 3)
        return String(raw[..<idx]) + " " + String(raw[idx...])
    }
}
