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
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case height, weight, age }

    private var heightCm: Double { Double(heightText) ?? 0 }
    private var weightKg: Double { Double(weightText) ?? 0 }
    private var ageYears: Int { Int(ageText) ?? 0 }

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
                    manualRow(icon: "scalemass", color: .pasteMint, label: "Weight (kg)", text: $weightText, field: .weight)
                    manualRow(icon: "calendar", color: .pastePeach, label: "Age (years)", text: $ageText, field: .age)
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
        if let w = saved.weightKg {
            weightText = String(format: "%.0f", w)
        } else if let w = p?.weightKg {
            weightText = String(format: "%.0f", w)
        }
        if let a = saved.ageYears {
            ageText = "\(a)"
        } else if let a = p?.ageYears {
            ageText = "\(a)"
        }
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
