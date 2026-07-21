// OnboardingAppBlockingView.swift — PRD §3D

import SwiftUI
import FamilyControls

struct OnboardingAppBlockingView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var hk = HealthKitService.shared
    @EnvironmentObject private var partnerVM: PartnerViewModel
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false

    private var progress: (current: Int, total: Int)? {
        PostAuthOnboardingStep.prdApps.progressIndicator(
            needsManualBody: hk.needsManualBodyMetrics,
            willShowRoleSelection: partnerVM.isPartnerPaired
        )
    }

    private var totalSelected: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    var body: some View {
        OnboardingScaffold(
            title: "Choose apps to lock",
            subtitle: "Pick the apps to lock until you hit today's goal.",
            stepIndex: progress?.current,
            stepCount: progress?.total,
            backAction: { auth.advancePRDOnboarding(to: .prdCalorie) },
            primaryTitle: totalSelected > 0 ? "Continue" : "Skip — pick later",
            primaryEnabled: true,
            primaryAction: {
                if totalSelected > 0 {
                    selection = ScreenTimeService.shared.saveSelection(selection)
                }
                auth.advancePRDOnboarding(to: .prdPairingPrompt)
            }
        ) {
            VStack(spacing: 14) {
                Button { showPicker = true } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.electricOrange.opacity(0.15))
                                .frame(width: 46, height: 46)
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.electricOrange)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(totalSelected > 0 ? "Edit selection" : "Open the picker")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.ink)
                            Text(totalSelected > 0
                                 ? "\(totalSelected) item\(totalSelected == 1 ? "" : "s") will be locked"
                                 : "Search any app — Sweat2Scroll can't be blocked")
                                .font(.system(size: 12))
                                .foregroundColor(.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.muted)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.electricOrange.opacity(0.4), lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(.plain)

                if totalSelected > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.emeraldGreen)
                        Text("\(totalSelected) selected — these will stay locked until your goal is met today.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.ink)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.emeraldGreen.opacity(0.10))
                    .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested categories")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.muted)
                        .tracking(0.8)
                    ForEach(["Social", "Games", "Entertainment"], id: \.self) { cat in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.electricOrange.opacity(0.2))
                                .frame(width: 6, height: 6)
                            Text(cat)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.ink)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 4)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.deepTeal)
                        .font(.system(size: 13))
                    Text("You can always refine this in Settings → Restricted Apps.")
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                }
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { newValue in
            let cleaned = newValue.excludingHostApplication()
            if cleaned != newValue {
                selection = cleaned
            }
        }
    }
}
