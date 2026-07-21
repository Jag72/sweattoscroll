// OnboardingPairingPromptView.swift — PRD §3E
// "Add an accountability partner?" — onboarding step 4/5.
//
// The three perk cards are tappable: each opens an `AccountabilityModeInfoSheet`
// that explains the mode and surfaces the user's connected partner(s) with
// their live goal-completion percentage. From inside that sheet the user can
// also start the pairing flow inline, so the page works equally well when the
// user is already paired or hasn't paired yet.
//
// The two main CTAs at the bottom remain the canonical pairing entry points.

import SwiftUI

struct OnboardingPairingPromptView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var hk = HealthKitService.shared
    @EnvironmentObject private var partnerVM: PartnerViewModel
    @State private var route: PairingRoute?
    @State private var infoMode: AccountabilityModeInfoSheet.Mode?

    private enum PairingRoute: String, Identifiable {
        case generate, enter
        var id: String { rawValue }
    }

    private var progress: (current: Int, total: Int)? {
        PostAuthOnboardingStep.prdPairingPrompt.progressIndicator(
            needsManualBody: hk.needsManualBodyMetrics,
            willShowRoleSelection: partnerVM.isPartnerPaired
        )
    }

    var body: some View {
        OnboardingScaffold(
            title: "Add an accountability partner?",
            subtitle: "Pair phones with a one-time 6-digit code.",
            stepIndex: progress?.current,
            stepCount: progress?.total,
            backAction: { auth.advancePRDOnboarding(to: .prdApps) },
            primaryTitle: "I'll generate a code",
            primaryAction: { route = .generate },
            secondaryTitle: "I have a code from my partner",
            secondaryAction: { route = .enter }
        ) {
            VStack(spacing: 14) {
                pairingPerk(.mutual,
                            title: "Mutual accountability",
                            sub: "Both burn calories, both stay honest")
                pairingPerk(.override,
                            title: "Emergency override",
                            sub: "Partner sends a fresh OTP when you're stuck")
                pairingPerk(.controller,
                            title: "Parent / coach mode",
                            sub: "One-way control if only one of you is participating")

                Button {
                    auth.advancePRDOnboarding(to: .prdComplete)
                } label: {
                    Text("Skip for now — I'll go solo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.muted)
                        .padding(.top, 4)
                }
            }
        }
        .sheet(item: $route, onDismiss: routeOnDismiss) { selected in
            NavigationStack {
                switch selected {
                case .generate: PairCodeGeneratorView()
                case .enter:    PairCodeEntryView()
                }
            }
        }
        .sheet(item: $infoMode) { mode in
            AccountabilityModeInfoSheet(mode: mode, partnerVM: partnerVM)
        }
        .task {
            // Best-effort fetch so the perk sheets open with fresh partner stats.
            await partnerVM.refreshPartnerData()
        }
    }

    /// When a pairing sheet dismisses, peek at the cached CloudKit account. If
    /// pairing actually succeeded (`isPaired == true`) we advance to the role
    /// selection step; otherwise the user can re-tap one of the buttons.
    private func routeOnDismiss() {
        Task {
            await auth.refreshAfterPairing()
            await MainActor.run {
                if auth.cachedAccount?.isPaired == true {
                    auth.advancePRDOnboarding(to: .prdRoleSelection)
                }
            }
        }
    }

    private func pairingPerk(_ mode: AccountabilityModeInfoSheet.Mode,
                             title: String,
                             sub: String) -> some View {
        Button {
            infoMode = mode
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(mode.tint.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: mode.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(mode.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.ink)
                        .multilineTextAlignment(.leading)
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if partnerVM.isPartnerPaired {
                    Text("\(Int((partnerVM.partnerProgressFraction * 100).rounded()))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(mode.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(mode.tint.opacity(0.12)))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

extension AccountabilityModeInfoSheet.Mode: Hashable {}
