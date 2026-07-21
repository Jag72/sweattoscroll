// OnboardingHealthView.swift — PRD §3A

import SwiftUI
import HealthKit

struct OnboardingHealthView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var hk = HealthKitService.shared
    @EnvironmentObject private var partnerVM: PartnerViewModel
    @State private var isRequesting = false
    @State private var connected = false
    @State private var errorMessage: String?

    private var progress: (current: Int, total: Int)? {
        PostAuthOnboardingStep.prdHealth.progressIndicator(
            needsManualBody: hk.needsManualBodyMetrics,
            willShowRoleSelection: partnerVM.isPartnerPaired
        )
    }

    private let perks: [(String, String, Color)] = [
        ("ruler",        "Height",              .pasteLavender),
        ("scalemass",    "Weight",              .pasteMint),
        ("calendar",     "Age",                 .pastePeach),
        ("flame.fill",   "Activity & calories", .pasteYellow),
    ]

    private var subtitleConnected: String {
        if hk.needsManualBodyMetrics {
            return "A few details are missing — you'll confirm them next."
        }
        return "Here's what we found. Continue to set your daily goal."
    }

    var body: some View {
        OnboardingScaffold(
            title: connected ? "You're connected to Apple Health" : "Let's personalize your goals",
            subtitle: connected ? subtitleConnected
                : "We'll use Apple Health to personalize your goal.",
            stepIndex: progress?.current,
            stepCount: progress?.total,
            primaryTitle: connected ? "Continue" : "Connect Apple Health",
            primaryEnabled: !isRequesting,
            primaryLoading: isRequesting,
            primaryAction: { handlePrimary() },
            secondaryTitle: connected ? nil : "Skip — I'll enter manually",
            secondaryAction: connected ? nil : { auth.advancePRDOnboarding(to: .prdManual) }
        ) {
            if connected {
                connectedSummary
                if hk.needsManualBodyMetrics {
                    incompleteBanner
                }
            } else {
                perksList
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.amber)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.ink)
                }
                .padding(12)
                .background(Color.amber.opacity(0.12))
                .cornerRadius(10)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.deepTeal)
                    .font(.system(size: 14))
                Text("Your health data stays on this device. Update height & weight anytime in Profile.")
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
                    .lineSpacing(2)
            }
            .padding(14)
            .background(Color.deepTeal.opacity(0.08))
            .cornerRadius(12)
        }
        .task { await refreshHealthConnection() }
    }

    private var incompleteBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.and.pencil")
                .foregroundColor(.electricOrange)
            Text("We'll confirm your height, weight & age on the next screen (fed by Apple Health when possible).")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.ink)
        }
        .padding(14)
        .background(Color.electricOrange.opacity(0.10))
        .cornerRadius(12)
    }

    private var perksList: some View {
        VStack(spacing: 12) {
            ForEach(perks.indices, id: \.self) { i in
                let p = perks[i]
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(p.2)
                            .frame(width: 42, height: 42)
                        Image(systemName: p.0)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.ink.opacity(0.85))
                    }
                    Text(p.1)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.ink)
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.muted.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                )
            }
        }
    }

    @ViewBuilder
    private var connectedSummary: some View {
        VStack(spacing: 12) {
            connectedRow(icon: "ruler", label: "Height",
                         value: formatHeight,
                         bg: .pasteLavender)
            connectedRow(icon: "scalemass", label: "Weight",
                         value: formatWeight,
                         bg: .pasteMint)
            connectedRow(icon: "calendar", label: "Age",
                         value: formatAge,
                         bg: .pastePeach)
            connectedRow(icon: "flame.fill", label: "Active calories today",
                         value: "\(Int(hk.activeCaloriesToday)) kcal",
                         bg: .pasteYellow)
        }
    }

    /// Prefer explicit saved manual ranges when HK merged profile still uses internal placeholders.
    private var formatHeight: String {
        let saved = UserBodyProfileStorage.load().heightCm
        let v = hk.userProfile?.heightCm ?? saved ?? 0
        guard v >= 120 && v <= 230 else { return "Not set — next screen" }
        return "\(Int(v)) cm"
    }

    private var formatWeight: String {
        let saved = UserBodyProfileStorage.load().weightKg
        let v = hk.userProfile?.weightKg ?? saved ?? 0
        guard v >= 30 && v <= 250 else { return "Not set — next screen" }
        let unit = WeightUnitPreference.load()
        let display = unit.fromKilograms(v)
        if unit == .kg {
            return String(format: "%.1f kg", display)
        }
        return String(format: "%.0f lb", display)
    }

    private var formatAge: String {
        let saved = UserBodyProfileStorage.load().ageYears
        let v = hk.userProfile?.ageYears ?? saved ?? 0
        guard v >= 13 && v <= 110 else { return "Not set — next screen" }
        return "\(v) yrs"
    }

    private func connectedRow(icon: String, label: String, value: String, bg: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(bg)
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.ink.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.muted)
                    .tracking(0.4)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.ink)
            }
            Spacer()
            Image(systemName: value.contains("Not set") ? "ellipsis.circle" : "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(value.contains("Not set") ? .amber : .emeraldGreen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - Actions

    @MainActor
    private func refreshHealthConnection() async {
        errorMessage = nil
        await hk.verifyAccess()

        if hk.hasAnsweredAuthorizationPrompt || hk.isAuthorized {
            try? await hk.fetchUserProfile()
            try? await hk.fetchTodayMetrics()
            connected = true
            return
        }

        // First visit — raise the system permission sheet automatically.
        guard hk.isHealthKitAvailable else {
            errorMessage = "HealthKit isn't available on this device. Tap Skip to enter your details manually."
            return
        }

        isRequesting = true
        defer { isRequesting = false }
        do {
            try await hk.requestAuthorization()
            connected = hk.hasAnsweredAuthorizationPrompt || hk.isAuthorized
        } catch HealthKitError.notAvailable {
            errorMessage = "HealthKit isn't available on this device. Tap Skip to enter your details manually."
        } catch {
            // The permission sheet may still have succeeded — re-check before alarming.
            await hk.verifyAccess()
            connected = hk.hasAnsweredAuthorizationPrompt || hk.isAuthorized
            if !connected {
                errorMessage = "Couldn't connect to Apple Health right now. Tap Connect to retry, or Skip to enter manually."
            }
        }
    }

    private func handlePrimary() {
        if connected {
            if hk.needsManualBodyMetrics {
                auth.advancePRDOnboarding(to: .prdManual)
            } else {
                auth.advancePRDOnboarding(to: .prdCalorie)
            }
            return
        }

        Task {
            isRequesting = true
            errorMessage = nil
            defer { isRequesting = false }
            do {
                try await hk.requestAuthorization()
                connected = hk.hasAnsweredAuthorizationPrompt || hk.isAuthorized
            } catch HealthKitError.notAvailable {
                errorMessage = "HealthKit isn't available on this device. Tap Skip to enter your details manually."
            } catch {
                await hk.verifyAccess()
                connected = hk.hasAnsweredAuthorizationPrompt || hk.isAuthorized
                if !connected {
                    errorMessage = "Couldn't connect to Apple Health right now. Try again or tap Skip to enter manually."
                }
            }
        }
    }
}
