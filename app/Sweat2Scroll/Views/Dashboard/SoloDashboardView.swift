// Views/Dashboard/SoloDashboardView.swift
// Solo mode — personal, self-accountability. Orange throughout.

import SwiftUI
import FamilyControls

struct SoloDashboardView: View {
    @EnvironmentObject private var activityVM: ActivityViewModel
    @EnvironmentObject private var wellnessVM: WellnessViewModel
    @ObservedObject private var blocking = BlockingSessionService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var tabIndex     = 0
    @State private var showBreakGlass = false
    @State private var showAppBlock = false
    @State private var showStandaloneJustification = false

    private let tabs: [NavTabItem] = [
        NavTabItem(label: "Home",     icon: "house.fill"),
        NavTabItem(label: "Progress", icon: "chart.line.uptrend.xyaxis"),
        NavTabItem(label: "Shield",   icon: "shield.fill"),
        NavTabItem(label: "Profile",  icon: "person.fill"),
    ]

    var body: some View {
        Color.paper.ignoresSafeArea()
            .overlay(
                Group {
                    switch tabIndex {
                    case 0: SoloHomeTab(showBreakGlass: $showBreakGlass,
                                        showAppBlock: $showAppBlock)
                    case 1: SoloProgressTab()
                    case 2: SoloShieldTab(showBreakGlass: $showBreakGlass,
                                          showAppBlock: $showAppBlock)
                    default: SoloProfileTab()
                    }
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppBottomNav(tabs: tabs, selection: $tabIndex)
                    .padding(.bottom, 8)
                    .background(Color.paper)
            }
            .sheet(isPresented: $showBreakGlass) {
                EmergencyOverrideView()
            }
            .fullScreenCover(isPresented: $showAppBlock) {
                AppBlockedShieldView(
                    kcalBurned: Int(activityVM.activityGoal.currentProgress),
                    kcalGoal:   Int(activityVM.activityGoal.agreedTarget),
                    onRequestFifteenMinuteBypass: { note in
                        activityVM.requestFifteenMinuteBypass(note: note)
                    },
                    onRequestDayBypass: {
                        activityVM.requestDayBypass()
                    }
                )
            }
            .sheet(isPresented: $showStandaloneJustification) {
                JustificationNoteSheet { note in
                    activityVM.requestFifteenMinuteBypass(note: note)
                    showStandaloneJustification = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CalorieObserver.goalMetNotification)) { _ in
                Task {
                    await activityVM.refreshFromHealthKit()
                    await wellnessVM.loadLiveData()
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                // The OS shield sets a flag in the App Group when the user taps
                // "Use 15 minutes" on the system block. Surface the
                // justification sheet as soon as they return to the app.
                if blocking.consumePendingJustification() {
                    showStandaloneJustification = true
                }
            }
    }
}

// MARK: - Home Tab

private struct SoloHomeTab: View {
    @Binding var showBreakGlass: Bool
    @Binding var showAppBlock: Bool
    @EnvironmentObject private var activityVM: ActivityViewModel
    @EnvironmentObject private var wellnessVM: WellnessViewModel
    @ObservedObject private var screenTime = ScreenTimeService.shared
    @ObservedObject private var hk = HealthKitService.shared
    @ObservedObject private var blocking = BlockingSessionService.shared

    private var remaining: Int {
        max(0, Int(activityVM.activityGoal.agreedTarget - activityVM.activityGoal.currentProgress))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {

                // Header
                AppDashHeader(
                    greeting: "Welcome back",
                    name:     AuthManager.shared.userDisplayName,
                    badge: AppDashBadge(
                        text: "14 day streak",
                        textColor: .electricOrange,
                        bg: Color.electricOrange.opacity(0.1)
                    )
                )
                .padding(.horizontal, 20)
                .padding(.top, 56)

                // Blocking-session banner. Tapping opens the in-app block screen
                // when apps are blocked so the user can "earn it" or buy a
                // 15-min bypass.
                BlockingStatusBanner(
                    phase: blocking.phase,
                    kcalRemaining: remaining,
                    graceMinutes: blocking.graceMinutesRemaining,
                    bypassMinutes: blocking.bypass15MinutesRemaining,
                    onTapBlocked: { showAppBlock = true }
                )
                .padding(.horizontal, 20)

                if hk.allTypesDenied {
                    HealthKitDeniedBanner()
                        .padding(.horizontal, 20)
                }

                // Hero card
                AppHeroCard(
                    calories: Int(activityVM.activityGoal.currentProgress),
                    steps:    activityVM.stepsToday,
                    fraction: activityVM.activityGoal.progressFraction,
                    locked:   !activityVM.isUnlocked
                )
                .padding(.horizontal, 20)

                // 2 × 2 stat tiles — pulled live from HealthKit
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    AppPastelTile(bg: .pasteLavender, icon: "heart.fill", iconColor: Color(hex: "#A897FF"),
                                  label: "Heart Rate",
                                  value: heartRateDisplay, unit: "bpm", sub: heartRateSub)
                    AppPastelTile(bg: .pasteMint, icon: "figure.walk", iconColor: Color(hex: "#34C99A"),
                                  label: "Steps",
                                  value: stepsDisplay, unit: "", sub: "today")
                    AppPastelTile(bg: .pastePeach, icon: "moon.fill", iconColor: Color(hex: "#FF9B85"),
                                  label: "Sleep",
                                  value: sleepValue, unit: sleepUnit, sub: sleepSub)
                    AppPastelTile(bg: .pasteYellow, icon: "bolt.fill", iconColor: Color(hex: "#E6A800"),
                                  label: "Energy",
                                  value: energyValue, unit: energyUnit,
                                  sub: energySub)
                }
                .padding(.horizontal, 20)

                // Weekly achievements — real per-day calorie history with
                // unlock streak + milestone badges.
                WeeklyAchievementsCard(
                    calorieHistory: hk.calorieHistory,
                    dailyGoal:      activityVM.activityGoal.agreedTarget
                )
                .padding(.horizontal, 20)

                // Biometrics
                DashSectionHeader(title: "Biometrics").padding(.horizontal, 20)
                AppBiometricStrip(
                    hrv:  wellnessVM.hrv,
                    rhr:  wellnessVM.rhr,
                    resp: wellnessVM.respiratoryRate
                )
                .padding(.horizontal, 20)

                // Restricted apps
                DashSectionHeader(title: "Restricted Apps").padding(.horizontal, 20)
                RestrictedAppsCard(
                    selectionCount: screenTime.activitySelection.applicationTokens.count
                                  + screenTime.activitySelection.categoryTokens.count
                                  + screenTime.activitySelection.webDomainTokens.count,
                    locked: !activityVM.isUnlocked
                )
                .padding(.horizontal, 20)

                // Break-glass
                AppBreakGlassTrigger(show: $showBreakGlass)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            .padding(.bottom, 16)
        }
        .task {
            await activityVM.refreshFromHealthKit()
            await wellnessVM.loadLiveData(from: HealthKitService.shared,
                                          moveGoalKcal: activityVM.activityGoal.agreedTarget)
        }
        .refreshable {
            await activityVM.refreshFromHealthKit()
            await wellnessVM.loadLiveData(from: HealthKitService.shared,
                                          moveGoalKcal: activityVM.activityGoal.agreedTarget)
        }
    }

    private var heartRateDisplay: String {
        if hk.heartRateLatest > 0 { return "\(Int(hk.heartRateLatest))" }
        if wellnessVM.rhr > 0     { return "\(Int(wellnessVM.rhr))" }
        return "—"
    }
    private var heartRateSub: String {
        hk.heartRateLatest > 0 ? "current" : "resting"
    }
    private var stepsDisplay: String {
        let n = activityVM.stepsToday
        if n == 0 { return "0" }
        return n >= 1000 ? String(format: "%.1fk", Double(n) / 1000.0) : "\(n)"
    }
    private var sleepValue: String {
        let h = wellnessVM.sleepDuration / 60
        return h > 0 ? String(format: "%.1f", h) : "—"
    }
    private var sleepUnit: String { wellnessVM.sleepDuration > 0 ? "hrs" : "" }
    private var sleepSub: String {
        guard wellnessVM.sleepDuration > 0 else { return "no data" }
        let h = Int(wellnessVM.sleepDuration) / 60
        let m = Int(wellnessVM.sleepDuration) % 60
        return "\(h)h \(m)m last night"
    }
    private var energyValue: String {
        wellnessVM.energyScore > 0 ? "\(Int(wellnessVM.energyScore))" : "—"
    }
    private var energyUnit: String { wellnessVM.energyScore > 0 ? "%" : "" }
    private var energySub: String {
        guard wellnessVM.energyScore > 0 else { return "move + stand" }
        return wellnessVM.energyScore >= 80 ? "fully charged"
             : wellnessVM.energyScore >= 50 ? "building up"
             : "low — keep moving"
    }

}

// MARK: - Restricted Apps Card

/// Single source of truth for the home Restricted Apps section. If the user
/// hasn't picked anything yet, shows an empty state pointing them to the picker
/// instead of fabricating fake app names.
private struct RestrictedAppsCard: View {
    let selectionCount: Int
    let locked: Bool

    var body: some View {
        DashCard {
            if selectionCount == 0 {
                VStack(spacing: 10) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.muted)
                    Text("No apps selected")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.ink)
                    Text("Pick the apps to lock from Settings → Restricted Apps.")
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Text("Restricted")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.ink)
                        Spacer()
                        Text(locked ? "All blocked" : "All open")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(locked ? .rose : .emeraldGreen)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(
                                Capsule().fill((locked ? Color.rose : Color.emeraldGreen).opacity(0.12))
                            )
                    }
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.electricOrange.opacity(0.15))
                                .frame(width: 46, height: 46)
                            Image(systemName: locked ? "lock.shield.fill" : "lock.open.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.electricOrange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(selectionCount) item\(selectionCount == 1 ? "" : "s")")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.ink)
                            Text(locked
                                 ? "Locked until your goal is met"
                                 : "Unlocked — you earned your scroll")
                                .font(.system(size: 11))
                                .foregroundColor(.muted)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Progress Tab

private struct SoloProgressTab: View {
    @EnvironmentObject private var wellnessVM: WellnessViewModel
    @EnvironmentObject private var activityVM: ActivityViewModel
    @ObservedObject private var hk = HealthKitService.shared

    var body: some View {
        ProgressScreen(
            energyScore:      wellnessVM.energyScore,
            moveProgress:     wellnessVM.moveProgress,
            exerciseProgress: wellnessVM.exerciseProgress,
            standProgress:    wellnessVM.standProgress,
            exerciseMinutes:  wellnessVM.exerciseMinutesToday,
            standHours:       wellnessVM.standHoursToday,
            caloriesToday:    wellnessVM.caloriesToday,
            stepsToday:       wellnessVM.stepsToday,
            hrv:              wellnessVM.hrv,
            rhr:              wellnessVM.rhr,
            resp:             wellnessVM.respiratoryRate,
            sleepHours:       wellnessVM.sleepDuration / 60,
            sleepEfficiency:  wellnessVM.sleepEfficiency,
            weekRHRAvg:       wellnessVM.weekRHRAvg,
            weekRHRMin:       wellnessVM.weekRHRMin,
            weekRHRMax:       wellnessVM.weekRHRMax,
            weekStepsAvg:     wellnessVM.weekStepsAvg,
            weekStepsBest:    wellnessVM.weekStepsBest,
            weekStepsTotal:   wellnessVM.weekStepsTotal,
            weekCaloriesAvg:  wellnessVM.weekCaloriesAvg,
            caloriesHistory:  wellnessVM.caloriesHistory,
            stepsHistory:     wellnessVM.stepsDailyHistory,
            heartHistory:     wellnessVM.rhrHistory,
            sleepHistory:     wellnessVM.sleepHistory,
            energyHistory:    wellnessVM.energyHistory,
            strainHistory:    wellnessVM.strainHistory,
            energyMoveGoalKcal: activityVM.activityGoal.agreedTarget
        )
        .task {
            await activityVM.refreshFromHealthKit()
            await wellnessVM.loadLiveData(from: HealthKitService.shared,
                                          moveGoalKcal: activityVM.activityGoal.agreedTarget)
        }
        .refreshable {
            await activityVM.refreshFromHealthKit()
            await wellnessVM.loadLiveData(from: HealthKitService.shared,
                                          moveGoalKcal: activityVM.activityGoal.agreedTarget)
        }
    }
}

// MARK: - Shield Tab

private struct SoloShieldTab: View {
    @EnvironmentObject private var activityVM: ActivityViewModel
    @ObservedObject private var screenTime = ScreenTimeService.shared
    @ObservedObject private var blocking = BlockingSessionService.shared
    @Binding var showBreakGlass: Bool
    @Binding var showAppBlock: Bool

    private var totalApps: Int {
        screenTime.activitySelection.applicationTokens.count
            + screenTime.activitySelection.categoryTokens.count
            + screenTime.activitySelection.webDomainTokens.count
    }

    var body: some View {
        ShieldScreen(
            isUnlocked:       activityVM.isUnlocked,
            calories:         Int(activityVM.activityGoal.currentProgress),
            goal:             Int(activityVM.activityGoal.agreedTarget),
            appsBlocked:      totalApps,
            blockedAppNames:  [],
            showBreakGlass:   $showBreakGlass,
            blockingPhase:    blocking.phase,
            graceMinutes:     blocking.graceMinutesRemaining,
            bypassMinutes:    blocking.bypass15MinutesRemaining,
            onTapShield:      { if blocking.phase == .blocked { showAppBlock = true } }
        )
        .task {
            await activityVM.refreshFromHealthKit()
        }
        .onAppear {
            screenTime.loadSelection()
        }
    }
}

// MARK: - Profile Tab

private struct SoloProfileTab: View {
    @EnvironmentObject private var activityVM: ActivityViewModel
    @ObservedObject private var screenTime = ScreenTimeService.shared
    @ObservedObject private var hk = HealthKitService.shared
    @State private var showRestrictedPicker = false
    @State private var showBodyMetricsSheet = false

    private var totalApps: Int {
        screenTime.activitySelection.applicationTokens.count
            + screenTime.activitySelection.categoryTokens.count
            + screenTime.activitySelection.webDomainTokens.count
    }

    private var bodyMetricsSummaryLine: String {
        guard let p = hk.userProfile else { return "Tap to set" }
        if hk.needsManualBodyMetrics {
            return "Finish setup · \(Int(p.heightCm)) cm · \(String(format: "%.0f", p.weightKg)) kg · \(p.ageYears) yrs"
        }
        return "\(Int(p.heightCm)) cm · \(String(format: "%.0f", p.weightKg)) kg · \(p.ageYears) yrs"
    }

    var body: some View {
        ProfileScreen(
            modeLabel:            "Solo Mode",
            modeColor:            .electricOrange,
            dailyGoal:            Int(activityVM.activityGoal.agreedTarget),
            appsBlocked:          totalApps,
            isPaired:             false,
            bodyMetricsSummary:   bodyMetricsSummaryLine,
            onEditBodyMetrics:    { showBodyMetricsSheet = true },
            onEditApps:           { showRestrictedPicker = true }
        )
        .onAppear {
            screenTime.loadSelection()
            Task {
                try? await hk.fetchUserProfile()
            }
        }
        .familyActivityPicker(isPresented: $showRestrictedPicker,
                              selection: $screenTime.activitySelection)
        .onChange(of: screenTime.activitySelection) { newValue in
            _ = screenTime.saveSelection(newValue)
        }
        .sheet(isPresented: $showBodyMetricsSheet) {
            BodyMetricsEditorSheet()
                .environmentObject(activityVM)
        }
    }
}
