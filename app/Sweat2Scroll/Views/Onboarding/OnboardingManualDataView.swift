// OnboardingManualDataView.swift — PRD §3B
// Inline text-field editor for height / weight / age. If Apple Health was
// authorized earlier, the fields auto-fill with the user's actual profile so
// they only have to confirm.

import SwiftUI

struct OnboardingManualDataView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var hk = HealthKitService.shared
    @EnvironmentObject private var activityVM: ActivityViewModel
    @EnvironmentObject private var partnerVM: PartnerViewModel

    private var progress: (current: Int, total: Int)? {
        PostAuthOnboardingStep.prdManual.progressIndicator(
            needsManualBody: true, // we're on this screen, so manual is part of the flow
            willShowRoleSelection: partnerVM.isPartnerPaired
        )
    }

    @State private var heightText: String = "170"
    @State private var weightText: String = "70"
    @State private var ageText:    String = "28"
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case height, weight, age }

    private var heightCm: Double { Double(heightText) ?? 0 }
    private var weightKg: Double { Double(weightText) ?? 0 }
    private var ageYears: Int    { Int(ageText) ?? 0 }
    private var heightM: Double  { heightCm / 100 }
    private var bmi: Double? {
        guard heightM > 0, weightKg > 0 else { return nil }
        return weightKg / (heightM * heightM)
    }
    private var canContinue: Bool {
        heightCm >= 120 && heightCm <= 230 &&
        weightKg >= 30  && weightKg <= 250 &&
        ageYears >= 13  && ageYears <= 110
    }

    var body: some View {
        OnboardingScaffold(
            title: "Tell us about you",
            subtitle: hk.userProfile != nil
                ? "We've pre-filled this from Apple Health. Edit anything that's off."
                : "These help us suggest a calorie goal that's safe and realistic.",
            stepIndex: progress?.current,
            stepCount: progress?.total,
            backAction: { auth.advancePRDOnboarding(to: .prdHealth) },
            primaryTitle: "Continue",
            primaryEnabled: canContinue,
            primaryAction: {
                Task {
                    let sex = hk.userProfile?.biologicalSex
                        ?? UserBodyProfileStorage.load().biologicalSex
                        ?? .other
                    await hk.applyManualBodyMetrics(
                        heightCm: heightCm,
                        weightKg: weightKg,
                        ageYears: ageYears,
                        biologicalSex: sex
                    )
                    if let bmi { UserDefaults.standard.set(bmi, forKey: "prdBMI") }
                    focusedField = nil
                    await MainActor.run {
                        activityVM.refreshActivityGoalFromProfile()
                        auth.advancePRDOnboarding(to: .prdCalorie)
                    }
                }
            }
        ) {
            VStack(spacing: 14) {
                inputCard(icon: "ruler", color: .pasteLavender, label: "Height",
                          unit: "cm", text: $heightText, field: .height,
                          decrement: { adjust(\.heightText, by: -1, min: 120, max: 230) },
                          increment: { adjust(\.heightText, by: 1, min: 120, max: 230) })

                inputCard(icon: "scalemass", color: .pasteMint, label: "Weight",
                          unit: "kg", text: $weightText, field: .weight,
                          decrement: { adjust(\.weightText, by: -1, min: 30, max: 250) },
                          increment: { adjust(\.weightText, by: 1, min: 30, max: 250) })

                inputCard(icon: "calendar", color: .pastePeach, label: "Age",
                          unit: "yrs", text: $ageText, field: .age,
                          decrement: { adjust(\.ageText, by: -1, min: 13, max: 110) },
                          increment: { adjust(\.ageText, by: 1, min: 13, max: 110) })

                if let bmi {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.deepTeal)
                        Text("BMI")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.muted)
                        Spacer()
                        Text(String(format: "%.1f", bmi))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.deepTeal)
                    }
                    .padding(14)
                    .background(Color.deepTeal.opacity(0.08))
                    .cornerRadius(12)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.electricOrange)
            }
        }
        .task {
            if hk.isAuthorized {
                try? await hk.fetchUserProfile()
            }
            hydrateFieldsFromProfileAndStorage()
        }
        .onReceive(hk.$userProfile) { _ in hydrateFieldsFromProfileAndStorage() }
    }

    private func hydrateFieldsFromProfileAndStorage() {
        let saved = UserBodyProfileStorage.load()
        let p = hk.userProfile
        if let h = saved.heightCm {
            heightText = "\(Int(h))"
        } else if let h = p?.heightCm, h >= 120 {
            heightText = "\(Int(h))"
        }
        if let w = saved.weightKg {
            weightText = String(format: "%.0f", w)
        } else if let w = p?.weightKg, w >= 30 {
            weightText = String(format: "%.0f", w)
        }
        if let a = saved.ageYears {
            ageText = "\(a)"
        } else if let a = p?.ageYears, a >= 13 {
            ageText = "\(a)"
        }
    }

    private func adjust(_ key: WritableKeyPath<OnboardingManualDataView, String>, by delta: Int, min: Int, max: Int) {
        let current = Int(self[keyPath: key]) ?? min
        let next = Swift.max(min, Swift.min(max, current + delta))
        switch key {
        case \.heightText: heightText = "\(next)"
        case \.weightText: weightText = "\(next)"
        case \.ageText:    ageText    = "\(next)"
        default: break
        }
    }

    // MARK: - Input row

    private func inputCard(icon: String, color: Color, label: String, unit: String,
                           text: Binding<String>, field: Field,
                           decrement: @escaping () -> Void,
                           increment: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color)
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ink.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0", text: text)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: field)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.ink)
                        .frame(maxWidth: 70)
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.muted)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                stepBtn(symbol: "minus", action: decrement)
                stepBtn(symbol: "plus", action: increment)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focusedField == field ? Color.electricOrange : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
    }

    private func stepBtn(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.ringTrack.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }
}
