// Views/Onboarding/UserOnboardingView.swift

import SwiftUI

struct UserOnboardingView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var step = 0
    @State private var name = ""
    @State private var age = "25"
    @State private var weight = "154"
    @State private var useMetric = false
    @State private var dailyTarget = "400"
    @State private var showPairEntry = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack {
                if step == 0 {
                    profileSteps
                } else {
                    pairIntro
                }
            }
        }
        .onAppear { name = auth.cachedAccount?.displayName ?? "" }
        .sheet(isPresented: $showPairEntry) {
            NavigationStack {
                PairCodeEntryView()
            }
        }
        .preferredColorScheme(.light)
    }

    private var profileSteps: some View {
        VStack(spacing: 20) {
            Text("Your profile")
                .font(.display(22))
                .padding(.top, 24)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            TextField("Age", text: $age)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            Picker("Units", selection: $useMetric) {
                Text("lbs").tag(false)
                Text("kg").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            TextField(useMetric ? "kg" : "lbs", text: $weight)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            TextField("Daily kcal goal", text: $dailyTarget)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.rose)
            }
            Button("Continue") {
                step = 1
            }
            .buttonStyle(.borderedProminent)
            .tint(.deepTeal)
            Spacer()
        }
    }

    private var pairIntro: some View {
        VStack(spacing: 24) {
            Text("Pair with your monitor")
                .font(.display(22))
                .multilineTextAlignment(.center)
                .padding(.top, 32)
            Text("Your monitor will give you a 6-digit code. Enter it now, or skip and add it from the dashboard.")
                .font(.body)
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Enter code now") {
                Task {
                    await saveProfile(skipPairing: true)
                    showPairEntry = true
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.electricOrange)

            Button("Skip for now") {
                Task { await saveProfile(skipPairing: true) }
            }
            .foregroundColor(.deepTeal)

            if isSaving { ProgressView() }
            Spacer()
        }
        .padding()
    }

    private func weightKg() -> Double? {
        guard let w = Double(weight) else { return nil }
        return useMetric ? w : w / 2.20462
    }

    private func saveProfile(skipPairing: Bool) async {
        guard let ageInt = Int(age), let wKg = weightKg(), let kcal = Double(dailyTarget) else {
            await MainActor.run { errorMessage = "Invalid profile values." }
            return
        }
        await MainActor.run { isSaving = true; errorMessage = nil }
        do {
            try await auth.completeUserOnboarding(
                displayName: name.isEmpty ? "Athlete" : name,
                ageYears: ageInt,
                weightKg: wKg,
                dailyTargetKcal: kcal,
                skipPairing: skipPairing
            )
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isSaving = false }
    }
}
