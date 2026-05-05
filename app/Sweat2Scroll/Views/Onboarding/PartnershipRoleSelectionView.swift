// PartnershipRoleSelectionView.swift
// Shown right after pairing succeeds so each device records *its own*
// `PartnershipRole`. Three options drive the rest of the app:
//   • mutual     → both partners track and can issue overrides for each other.
//   • controller → I monitor my partner; only I can issue OTPs (parent mode).
//   • controlled → my apps are the ones gated; partner sends OTPs to unlock me.

import SwiftUI

struct PartnershipRoleSelectionView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var hk = HealthKitService.shared
    @State private var selected: PartnershipRole = .mutual
    @State private var isSaving = false

    private var progress: (current: Int, total: Int)? {
        PostAuthOnboardingStep.prdRoleSelection.progressIndicator(
            needsManualBody: hk.needsManualBodyMetrics,
            willShowRoleSelection: true
        )
    }

    var body: some View {
        OnboardingScaffold(
            title: "How do you want to support each other?",
            subtitle: "You can change this anytime in settings. Your partner picks their own role on their phone.",
            stepIndex: progress?.current,
            stepCount: progress?.total,
            backAction: { auth.advancePRDOnboarding(to: .prdPairingPrompt) },
            primaryTitle: isSaving ? "Saving…" : "Confirm role",
            primaryAction: confirm,
            secondaryTitle: nil,
            secondaryAction: nil
        ) {
            VStack(spacing: 12) {
                ForEach(PartnershipRole.allCases, id: \.self) { role in
                    roleCard(role)
                }
            }
        }
    }

    private func confirm() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            await auth.finishPostPairingRoleSelection(selected)
            await MainActor.run {
                isSaving = false
                auth.advancePRDOnboarding(to: .prdComplete)
            }
        }
    }

    @ViewBuilder
    private func roleCard(_ role: PartnershipRole) -> some View {
        let isSelected = selected == role
        Button {
            selected = role
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.electricOrange : Color.ringTrack,
                            lineWidth: 2
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color.electricOrange).frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: roleIcon(role))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.electricOrange)
                        Text(role.displayTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ink)
                    }
                    Text(role.displaySubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    rolePerks(role)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.electricOrange : Color.ringTrack.opacity(0.6),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.06 : 0.03), radius: isSelected ? 10 : 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func roleIcon(_ role: PartnershipRole) -> String {
        switch role {
        case .mutual:     return "arrow.triangle.2.circlepath"
        case .controller: return "person.crop.circle.badge.checkmark"
        case .controlled: return "lock.shield"
        }
    }

    @ViewBuilder
    private func rolePerks(_ role: PartnershipRole) -> some View {
        let items: [String] = {
            switch role {
            case .mutual:
                return ["Both track calories", "Either of us can grant override OTPs"]
            case .controller:
                return ["My phone isn't blocked", "I generate override OTPs for my partner"]
            case .controlled:
                return ["My apps are blocked until I hit my goal", "Partner sends an OTP to unlock me"]
            }
        }()
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { line in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.emeraldGreen)
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                }
            }
        }
        .padding(.top, 6)
    }
}
