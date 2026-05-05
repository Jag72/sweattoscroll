// Views/Onboarding/SoloOnboardingView.swift

import SwiftUI

struct SoloOnboardingView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var step = 0
    @State private var name = ""
    @State private var age = "25"
    @State private var weight = "154"
    @State private var useMetric = false
    @State private var dailyTarget = "400"
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(spacing: 20) {
                progressDots
                Group {
                    switch step {
                    case 0: stepNameAge
                    case 1: stepWeight
                    case 2: stepGoal
                    default: stepOptionalPartner
                    }
                }
                .animation(.easeInOut, value: step)

                Spacer()

                HStack {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .foregroundColor(.muted)
                    }
                    Spacer()
                    if step < 3 {
                        Button("Continue") { advance() }
                            .font(.headline)
                            .foregroundColor(.electricOrange)
                            .disabled(isSaving)
                    } else {
                        Button("Finish") { finish() }
                            .font(.headline)
                            .foregroundColor(.electricOrange)
                            .disabled(isSaving)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.rose)
                }
                if isSaving { ProgressView() }
            }
        }
        .onAppear {
            name = auth.cachedAccount?.displayName ?? ""
        }
        .preferredColorScheme(.light)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i <= step ? Color.electricOrange : Color.ringTrack)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 24)
    }

    private var stepNameAge: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About you")
                .font(.display(22))
                .foregroundColor(.ink)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Age", text: $age)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Spacer()
        }
        .padding(24)
    }

    private var stepWeight: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weight")
                .font(.display(22))
                .foregroundColor(.ink)
            Picker("Units", selection: $useMetric) {
                Text("lbs").tag(false)
                Text("kg").tag(true)
            }
            .pickerStyle(.segmented)
            TextField(useMetric ? "Kilograms" : "Pounds", text: $weight)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            Spacer()
        }
        .padding(24)
    }

    private var stepGoal: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily active calorie goal")
                .font(.display(22))
                .foregroundColor(.ink)
            TextField("kcal", text: $dailyTarget)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Text("We use Mifflin–St Jeor from your weight & age where HealthKit allows.")
                .font(.caption)
                .foregroundColor(.muted)
            Spacer()
        }
        .padding(24)
    }

    private var stepOptionalPartner: some View {
        VStack(spacing: 20) {
            Text("Add a monitor later?")
                .font(.display(22))
                .foregroundColor(.ink)
            Text("You can pair with someone anytime from the dashboard.")
                .font(.subheadline)
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private func weightKgValue() -> Double? {
        guard let w = Double(weight) else { return nil }
        return useMetric ? w : w / 2.20462
    }

    private func advance() {
        errorMessage = nil
        if step < 3 { step += 1 }
    }

    private func finish() {
        guard let ageInt = Int(age), let wKg = weightKgValue(), let kcal = Double(dailyTarget) else {
            errorMessage = "Check your numbers."
            return
        }
        isSaving = true
        Task {
            do {
                try await auth.completeSoloOnboarding(
                    displayName: name.isEmpty ? "Athlete" : name,
                    ageYears: ageInt,
                    weightKg: wKg,
                    dailyTargetKcal: kcal
                )
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isSaving = false }
        }
    }
}
