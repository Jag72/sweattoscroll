// OnboardingCompleteView.swift — PRD §3F

import SwiftUI

struct OnboardingCompleteView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var busy = false
    @State private var error: String?

    private var goal: Double {
        UserDefaults.standard.double(forKey: "dailyCalorieGoal")
    }

    private var appCount: Int {
        ScreenTimeService.shared.activitySelection.applicationTokens.count
            + ScreenTimeService.shared.activitySelection.categoryTokens.count
    }

    private var displayName: String {
        let u = UserDefaults.standard.string(forKey: "prdUsername") ?? ""
        if !u.isEmpty { return u }
        return auth.cachedAccount?.displayName ?? "Athlete"
    }

    var body: some View {
        OnboardingScaffold(
            title: "You're ready to earn your scroll!",
            subtitle: "Every day, your apps stay locked until you hit your goal. Move first, scroll later.",
            backAction: { auth.advancePRDOnboarding(to: .prdPairingPrompt) },
            primaryTitle: "Start Sweating",
            primaryEnabled: !busy,
            primaryLoading: busy,
            primaryAction: { Task { await finish() } }
        ) {
            VStack(spacing: 14) {
                summaryCard

                statRow(icon: "flame.fill", label: "Daily calorie goal",
                        value: "\(Int(goal)) kcal", color: .electricOrange)
                statRow(icon: "app.badge.checkmark", label: "Apps to shield",
                        value: appCount > 0 ? "\(appCount)" : "Pick later",
                        color: .deepTeal)
                statRow(icon: "person.fill", label: "Account",
                        value: displayName, color: .amber)

                if let error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                        Text(error).font(.caption)
                    }
                    .foregroundColor(.rose)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.rose.opacity(0.10))
                    .cornerRadius(10)
                }
            }
        }
        .onAppear { ScreenTimeService.shared.loadSelection() }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.electricOrange, Color(hex: "#FF9A62")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.electricOrange.opacity(0.35), radius: 14, y: 6)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(.white)
            }
            Text("Ready when you are")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        )
    }

    private func statRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.ink)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    @MainActor
    private func finish() async {
        busy = true
        error = nil
        defer { busy = false }
        let age = UserDefaults.standard.object(forKey: "prdAgeYears") as? Int
        let w = UserDefaults.standard.object(forKey: "prdWeightKg") as? Double
        do {
            try await auth.finishPRDOnboardingFlow(
                displayName: displayName,
                calorieGoal: max(goal, 100),
                ageYears: age,
                weightKg: w
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
