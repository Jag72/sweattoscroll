// Views/Profile/BodyMetricsEditorSheet.swift
// Lets users update height / weight / age after onboarding (Profile tab).

import SwiftUI

struct BodyMetricsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activityVM: ActivityViewModel
    @ObservedObject private var hk = HealthKitService.shared

    @State private var heightText: String = "170"
    @State private var weightText: String = "70"
    @State private var ageText: String = "28"
    @State private var weightUnit: WeightUnit = WeightUnitPreference.load()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case height, weight, age }

    private var heightCm: Double { Double(heightText) ?? 0 }
    private var weightKg: Double { weightUnit.toKilograms(Double(weightText) ?? 0) }
    private var ageYears: Int { Int(ageText) ?? 0 }
    private var heightM: Double { heightCm / 100 }
    private var bmi: Double? {
        guard heightM > 0, weightKg > 0 else { return nil }
        return weightKg / (heightM * heightM)
    }

    private var canSave: Bool {
        heightCm >= 120 && heightCm <= 230 &&
        weightKg >= 30 && weightKg <= 250 &&
        ageYears >= 13 && ageYears <= 110
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Used with Apple Health data when available. Editing here saves to Sweat2Scroll and keeps your calorie goal accurate.")
                        .font(.system(size: 14))
                        .foregroundColor(.muted)

                    manualRow(icon: "ruler", color: .pasteLavender, label: "Height (cm)", text: $heightText, field: .height)
                    weightRow
                    manualRow(icon: "calendar", color: .pastePeach, label: "Age (years)", text: $ageText, field: .age)

                    if let bmi {
                        let cat = BMICategory.from(bmi: bmi)
                        let recommended = CalorieRecommendation.dailyActiveBurn(bmi: bmi, weightKg: weightKg)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("BMI \(String(format: "%.1f", bmi)) · \(cat.rawValue)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.deepTeal)
                                Spacer()
                                Text("\(Int(recommended)) kcal/day")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.electricOrange)
                            }
                            Text(cat.guidance)
                                .font(.system(size: 12))
                                .foregroundColor(.muted)
                        }
                        .padding(14)
                        .background(Color.deepTeal.opacity(0.08))
                        .cornerRadius(12)
                    }
                }
                .padding(24)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Your details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
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
                            activityVM.refreshActivityGoalFromProfile()
                            await activityVM.evaluatePolicy()
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .onAppear { hydrateFromCurrentState() }
    }

    private func hydrateFromCurrentState() {
        let saved = UserBodyProfileStorage.load()
        let p = hk.userProfile
        if let h = saved.heightCm {
            heightText = "\(Int(h))"
        } else if let h = p?.heightCm {
            heightText = "\(Int(h))"
        }
        let knownKg = saved.weightKg ?? p?.weightKg
        if let w = knownKg {
            weightText = String(Int(weightUnit.fromKilograms(w).rounded()))
        }
        if let a = saved.ageYears {
            ageText = "\(a)"
        } else if let a = p?.ageYears {
            ageText = "\(a)"
        }
    }

    private func setWeightUnit(_ newUnit: WeightUnit) {
        guard newUnit != weightUnit else { return }
        let kg = weightUnit.toKilograms(Double(weightText) ?? 0)
        weightUnit = newUnit
        weightText = String(Int(newUnit.fromKilograms(kg).rounded()))
        WeightUnitPreference.save(newUnit)
    }

    private func adjustWeight(by delta: Double) {
        let range = weightUnit.range
        let current = Double(weightText) ?? range.lowerBound
        let next = Swift.max(range.lowerBound, Swift.min(range.upperBound, current + delta))
        weightText = String(Int(next))
    }

    private var weightRow: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.pasteMint)
                    .frame(width: 42, height: 42)
                Image(systemName: "scalemass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ink.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Weight")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.muted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.ink)
                        .frame(maxWidth: 56)
                    unitToggle
                }
            }
            Spacer()
            HStack(spacing: 8) {
                weightStepBtn(symbol: "minus") { adjustWeight(by: -1) }
                weightStepBtn(symbol: "plus") { adjustWeight(by: 1) }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private var unitToggle: some View {
        HStack(spacing: 0) {
            ForEach(WeightUnit.allCases, id: \.self) { u in
                Button { setWeightUnit(u) } label: {
                    Text(u.label)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 34, height: 26)
                        .background(weightUnit == u ? Color.electricOrange : Color.clear)
                        .foregroundColor(weightUnit == u ? .white : .muted)
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ringTrack.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func weightStepBtn(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.ringTrack.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    private func manualRow(icon: String, color: Color, label: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color)
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ink.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.muted)
                TextField("", text: text)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: field)
                    .font(.system(size: 18, weight: .bold))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}
