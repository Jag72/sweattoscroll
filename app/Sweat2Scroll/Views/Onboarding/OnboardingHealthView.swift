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
            return "Apple Health didn't include everything we need (or samples are missing). Tap Continue to confirm height, weight & age in Sweat2Scroll."
        }
        return "We pulled your latest profile from Apple Health. Tap Continue to set your daily target."
    }

    var body: some View {
        OnboardingScaffold(
            title: connected ? "You're connected to Apple Health" : "Let's personalize your goals",
            subtitle: connected ? subtitleConnected
                : "We'll read age, weight & height from Apple Health when available — otherwise you'll enter them in Sweat2Scroll.",
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

            if hk.allTypesDenied {
                deniedBanner
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
        .task {
            // 1. If iOS already remembers a previous grant, refresh data and
            //    flip to "connected" without showing the system sheet again.
            if hk.isAuthorized {
                try? await hk.fetchUserProfile()
                try? await hk.fetchTodayMetrics()
                await hk.verifyAccess()
                connected = hk.isAuthorized
                return
            }

            // 2. Otherwise, proactively raise the system permission sheet so the
            //    user doesn't have to hunt for the "Connect" button. iOS will
            //    no-op silently if it's already been granted/denied — we then
            //    use `verifyAccess()` to detect denial and surface a banner.
            guard hk.isHealthKitAvailable else { return }
            do {
                isRequesting = true
                try await hk.requestAuthorization()
                connected = hk.isAuthorized
            } catch {
                // Don't surface an error yet — the user can still tap the
                // primary button to retry, or skip into manual entry.
            }
            isRequesting = false
        }
    }

    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.rose)
                Text("Apple Health is currently blocking access. Open Settings → Health → Data Access & Devices → Sweat2Scroll and enable the categories so we can read your activity.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ink)
            }
            Button {
                if let url = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(url)
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Health settings")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.rose)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rose.opacity(0.10))
        .cornerRadius(12)
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
        return String(format: "%.1f kg", v)
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
            do {
                try await hk.requestAuthorization()
                connected = true
            } catch {
                errorMessage = "Apple Health access was not granted. You can enter your details manually instead."
            }
            isRequesting = false
        }
    }
}
