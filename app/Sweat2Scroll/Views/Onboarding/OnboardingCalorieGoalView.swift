// OnboardingCalorieGoalView.swift — PRD §3C

import SwiftUI

struct OnboardingCalorieGoalView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var hk = HealthKitService.shared
    @EnvironmentObject private var partnerVM: PartnerViewModel
    @State private var goal: Double = 0

    private var progress: (current: Int, total: Int)? {
        PostAuthOnboardingStep.prdCalorie.progressIndicator(
            needsManualBody: hk.needsManualBodyMetrics,
            willShowRoleSelection: partnerVM.isPartnerPaired
        )
    }

    private var previous: PostAuthOnboardingStep? {
        PostAuthOnboardingStep.prdCalorie.previousStep(
            needsManualBody: hk.needsManualBodyMetrics,
            willShowRoleSelection: partnerVM.isPartnerPaired
        )
    }

    private var backTarget: (() -> Void)? {
        guard let step = previous else { return nil }
        return { auth.advancePRDOnboarding(to: step) }
    }

    private var storedBMI: Double? {
        UserDefaults.standard.object(forKey: "prdBMI") as? Double
    }

    private var profileWeightKg: Double? {
        hk.userProfile?.weightKg ?? UserBodyProfileStorage.load().weightKg
    }

    /// BMI-informed daily active-calorie-burn recommendation (see
    /// `CalorieRecommendation`). Higher BMI → a larger, still-realistic target
    /// so the user trends toward a healthier range over time.
    private var recommended: Double {
        CalorieRecommendation.dailyActiveBurn(bmi: storedBMI, weightKg: profileWeightKg)
    }

    private var selectedOrRecommended: Double {
        goal > 0 ? goal : recommended
    }

    var body: some View {
        OnboardingScaffold(
            title: "Set your daily calorie burn goal",
            subtitle: "We've calculated a recommended target based on your profile. You can adjust this anytime in Settings.",
            stepIndex: progress?.current,
            stepCount: progress?.total,
            backAction: backTarget,
            primaryTitle: "Continue",
            primaryEnabled: selectedOrRecommended > 0,
            primaryAction: {
                let v = selectedOrRecommended
                UserDefaults.standard.set(v, forKey: "dailyCalorieGoal")
                auth.advancePRDOnboarding(to: .prdApps)
            }
        ) {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("\(Int(selectedOrRecommended))")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundColor(.electricOrange)
                    Text("KCAL / DAY")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.muted)
                        .tracking(1.4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                )

                if let bmi = storedBMI {
                    let cat = BMICategory.from(bmi: bmi)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.deepTeal)
                            .font(.system(size: 15))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Based on your BMI \(String(format: "%.1f", bmi)) (\(cat.rawValue))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.ink)
                            Text("\(cat.guidance) We suggest burning about \(Int(recommended)) kcal a day to keep building fitness.")
                                .font(.system(size: 12))
                                .foregroundColor(.muted)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.deepTeal.opacity(0.08))
                    .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Pick your goal")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.muted)
                        Spacer()
                        Text("Recommended \(Int(recommended)) kcal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.electricOrange)
                    }
                    Slider(value: Binding(
                        get: { goal > 0 ? goal : recommended },
                        set: { goal = $0 }
                    ), in: 100...1500, step: 25)
                    .tint(.electricOrange)
                    HStack {
                        Text("100").font(.caption2).foregroundColor(.muted)
                        Spacer()
                        Text("1500").font(.caption2).foregroundColor(.muted)
                    }
                }

                HStack(spacing: 8) {
                    presetChip(label: "Light", value: 250)
                    presetChip(label: "Moderate", value: 400)
                    presetChip(label: "Athlete", value: 600)
                }
            }
        }
        .onAppear {
            if goal == 0 { goal = recommended }
        }
    }

    private func presetChip(label: String, value: Double) -> some View {
        let isSelected = abs(selectedOrRecommended - value) < 1
        return Button {
            goal = value
        } label: {
            VStack(spacing: 2) {
                Text("\(Int(value))")
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.electricOrange : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.electricOrange : Color.ringTrack, lineWidth: 1)
                    )
            )
            .foregroundColor(isSelected ? .white : .ink)
        }
        .buttonStyle(.plain)
    }
}
