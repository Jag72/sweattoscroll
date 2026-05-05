// Views/Onboarding/MonitorOnboardingView.swift

import SwiftUI
import FamilyControls

struct MonitorOnboardingView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var step = 0
    @State private var name = ""
    @State private var relationship = "Partner"
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection()
    @State private var scrollRatio = "10.0"
    @State private var dailyCap = "60"
    @State private var authError: String?

    private let relations = ["Parent", "Partner", "Coach", "Friend"]

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(spacing: 20) {
                switch step {
                case 0: stepProfile
                case 1: stepScreenTime
                default: stepPolicy
                }
                Spacer()
                HStack {
                    if step > 0 && step < 3 {
                        Button("Back") { step -= 1 }.foregroundColor(.muted)
                    }
                    Spacer()
                    if step < 2 {
                        Button("Continue") { step += 1 }
                            .foregroundColor(.electricOrange)
                    } else if step == 2 {
                        Button("Generate pair code") {
                            Task { await finishProfileAndShowCode() }
                        }
                        .foregroundColor(.electricOrange)
                    }
                }
                .padding()
            }
        }
        .onAppear { name = auth.cachedAccount?.displayName ?? "" }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { newValue in
            let cleaned = newValue.excludingHostApplication()
            if cleaned != newValue {
                selection = cleaned
            }
        }
        .preferredColorScheme(.light)
    }

    private var stepProfile: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monitor profile")
                .font(.display(22))
                .padding(.top, 24)
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("Relationship", selection: $relationship) {
                ForEach(relations, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Spacer()
        }
        .padding(24)
    }

    private var stepScreenTime: some View {
        VStack(spacing: 20) {
            Text("Screen Time")
                .font(.display(22))
            Text("Sweat2Scroll needs Screen Time permission so you can shield apps for the person you monitor.")
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Request authorization") {
                Task {
                    await ScreenTimeService.shared.requestAuthorization()
                    if ScreenTimeService.shared.authorizationStatus != .approved {
                        authError = "Permission not granted."
                    } else {
                        authError = nil
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.deepTeal)
            if let authError { Text(authError).font(.caption).foregroundColor(.rose) }
            Spacer()
        }
        .padding()
    }

    private var stepPolicy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Policy setup")
                .font(.display(22))
            TextField("Scroll ratio (kcal per minute est.)", text: $scrollRatio)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Daily scroll cap (minutes)", text: $dailyCap)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Button("Choose allowed apps") { showPicker = true }
                .buttonStyle(.bordered)
            Text("\(selection.applicationTokens.count) apps selected — search in Apple's picker; Sweat2Scroll can't be blocked.")
                .font(.caption)
                .foregroundColor(.muted)
            Spacer()
        }
        .padding(24)
    }

    private func finishProfileAndShowCode() async {
        do {
            try await auth.completeMonitorOnboarding(
                displayName: name.isEmpty ? "Monitor" : name,
                relationship: relationship
            )
            selection = ScreenTimeService.shared.saveSelection(selection)
        } catch {
            await MainActor.run { authError = error.localizedDescription }
        }
    }
}
