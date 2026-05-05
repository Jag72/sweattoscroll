// Views/Pairing/EmergencyOverrideView.swift
// Partner-issued emergency override flow used after pairing succeeds.
//
// Two tabs:
//   • Receive — paste the 6-digit OTP my partner just sent. We validate it
//     against the matching `BypassGrant` CloudKit record, drop the master
//     shield + Sweat2Scroll's blocking phase for the granted minutes, and log
//     the event.
//   • Send — pick how many minutes I want to grant my partner, generate a
//     fresh OTP, and show it large so I can read it to them. Persists to
//     CloudKit so their device can validate it.
//
// Tabs are gated by the local `PartnershipRole`:
//   - `controlled` → Receive only.
//   - `controller` → Send only.
//   - `mutual`     → Both tabs.

import SwiftUI

struct EmergencyOverrideView: View {
    @ObservedObject private var auth = AuthManager.shared
    @EnvironmentObject private var partnerVM: PartnerViewModel
    @EnvironmentObject private var activityVM: ActivityViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .receive
    @State private var receiveDigits: [String] = Array(repeating: "", count: 6)
    @FocusState private var receiveFocus: Int?
    @State private var receiveStatus: Status = .idle
    @State private var isSubmitting = false
    @State private var sendDuration: Int = 30
    @State private var sendReason: String = ""
    @State private var lastIssued: EmergencyOverrideGrant?
    @State private var sendStatus: Status = .idle

    private enum Mode: String, CaseIterable, Identifiable {
        case receive, send
        var id: String { rawValue }
        var label: String { self == .receive ? "Receive code" : "Send code" }
    }

    private enum Status: Equatable {
        case idle
        case info(String)
        case success(String)
        case error(String)
    }

    private var role: PartnershipRole {
        auth.cachedAccount?.partnershipRole ?? .mutual
    }
    private var canReceive: Bool { role.canRedeemOverride }
    private var canSend: Bool { role.canGrantOverride }
    private var partnerName: String {
        partnerVM.partnerDisplayName.isEmpty ? "Your partner" : partnerVM.partnerDisplayName
    }
    private var availableModes: [Mode] {
        [canReceive ? Mode.receive : nil, canSend ? Mode.send : nil].compactMap { $0 }
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

                    if !partnerVM.isPartnerPaired {
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
            }
        }
    }

    // MARK: - Subviews

    private var unpairedNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 38))
                .foregroundColor(.muted.opacity(0.4))
            Text("Pair with a partner first")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.ink)
            Text("Once you've shared a 6-digit pair code with your partner, you'll be able to send and receive emergency override OTPs from this screen.")
                .font(.system(size: 13))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.top, 40)
    }

    private var receivePane: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Enter the code from \(partnerName)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.center)
                Text("Codes are valid for 10 minutes after they're sent.")
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    TextField("", text: Binding(
                        get: { receiveDigits[i] },
                        set: { new in
                            let trimmed = String(new.filter(\.isNumber).prefix(1))
                            receiveDigits[i] = trimmed
                            if !trimmed.isEmpty, i < 5 { receiveFocus = i + 1 }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .frame(width: 44, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.ringTrack, lineWidth: 2)
                    )
                    .focused($receiveFocus, equals: i)
                }
            }

            statusLabel(receiveStatus)

            Button(action: submitReceived) {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(.white) }
                    Text(isSubmitting ? "Validating…" : "Unlock with this code")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.electricOrange.opacity(receiveCode.count == 6 ? 1 : 0.4))
                )
            }
            .disabled(isSubmitting || receiveCode.count != 6)
            .padding(.horizontal, 20)

            Text("This unlocks your blocked apps for the duration your partner picked when they sent the code.")
                .font(.system(size: 12))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .onAppear { receiveFocus = 0 }
    }

    private var sendPane: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Send a code to \(partnerName)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ink)
                Text("Pick how long you want their apps to stay unlocked.")
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            durationPicker

            VStack(alignment: .leading, spacing: 6) {
                Text("Reason (optional)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.muted)
                    .tracking(0.6)
                TextField("Sick day, traveling, …", text: $sendReason)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ringTrack, lineWidth: 1))
                    )
            }
            .padding(.horizontal, 20)

            if let issued = lastIssued {
                issuedCodeCard(issued)
            }

            statusLabel(sendStatus)

            Button(action: generateSendCode) {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(.white) }
                    Image(systemName: "paperplane.fill")
                    Text(isSubmitting ? "Generating…" : (lastIssued == nil ? "Generate \(sendDuration)-min code" : "Generate a fresh code"))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.electricOrange)
                )
            }
            .disabled(isSubmitting)
            .padding(.horizontal, 20)
        }
    }

    private var durationPicker: some View {
        let presets = [15, 30, 45, 60, 90]
        return VStack(alignment: .leading, spacing: 8) {
            Text("DURATION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.muted)
                .tracking(0.8)
                .padding(.horizontal, 20)
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { v in
                    Button { sendDuration = v } label: {
                        Text("\(v)m")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(sendDuration == v ? .white : .ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(sendDuration == v ? Color.electricOrange : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(sendDuration == v ? Color.electricOrange : Color.ringTrack, lineWidth: 1.5)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func issuedCodeCard(_ grant: EmergencyOverrideGrant) -> some View {
        VStack(spacing: 10) {
            Text("CODE FOR \(partnerName.uppercased())")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.muted)
                .tracking(0.8)
            Text(grant.code)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .tracking(8)
                .foregroundColor(.electricOrange)
                .padding(.vertical, 10)
            Text("Unlocks \(grant.durationMinutes) minutes • Expires \(timeRemainingString(until: grant.expiresAt))")
                .font(.system(size: 12))
                .foregroundColor(.muted)
            Button {
                UIPasteboard.general.string = grant.code
            } label: {
                Label("Copy code", systemImage: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.deepTeal)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.electricOrange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.electricOrange.opacity(0.25), lineWidth: 1.5)
                )
        )
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func statusLabel(_ status: Status) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .info(let msg):
            Text(msg).font(.caption).foregroundColor(.muted).multilineTextAlignment(.center)
        case .success(let msg):
            Label(msg, systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold)).foregroundColor(.emeraldGreen)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold)).foregroundColor(.rose)
        }
    }

    // MARK: - Actions

    private var receiveCode: String { receiveDigits.joined() }

    private var partnerUserID: String? {
        let peer = auth.cachedAccount?.linkedPeerAppleUserID ?? ""
        return peer.isEmpty ? nil : peer
    }

    private func submitReceived() {
        guard let myID = auth.currentAppleUserID, let peerID = partnerUserID else {
            receiveStatus = .error("You're not paired with a partner yet.")
            return
        }
        isSubmitting = true
        receiveStatus = .idle
        let code = receiveCode
        Task {
            do {
                let grant = try await EmergencyOverrideService.shared.redeemGrant(
                    code: code, recipientUserID: myID, partnerUserID: peerID
                )
                await MainActor.run {
                    activityVM.applyEmergencyOverride(
                        durationMinutes: grant.durationMinutes,
                        grantedBy: grant.granterDisplayName,
                        reason: grant.reason
                    )
                    isSubmitting = false
                    receiveStatus = .success("Apps unlocked for \(grant.durationMinutes) minutes")
                    receiveDigits = Array(repeating: "", count: 6)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    receiveStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func generateSendCode() {
        guard let myID = auth.currentAppleUserID, let peerID = partnerUserID else {
            sendStatus = .error("You're not paired with a partner yet.")
            return
        }
        isSubmitting = true
        sendStatus = .idle
        let duration = sendDuration
        let reason = sendReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let granterName = AuthManager.shared.userDisplayName
        Task {
            do {
                let grant = try await EmergencyOverrideService.shared.issueGrant(
                    granterUserID: myID,
                    granterDisplayName: granterName,
                    recipientUserID: peerID,
                    durationMinutes: duration,
                    reason: reason
                )
                await MainActor.run {
                    isSubmitting = false
                    lastIssued = grant
                    sendStatus = .info("Share this code with \(partnerName). They'll unlock for \(duration) min.")
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    sendStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func timeRemainingString(until date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
