// Views/Dashboard/UserDashboardView.swift
// User (monitored) mode — same layout language as Solo, partner-awareness added via badge + strips.

import SwiftUI

struct UserDashboardView: View {
    let isPaired: Bool

    @ObservedObject private var auth = AuthManager.shared
    @EnvironmentObject private var activityVM: ActivityViewModel
    @EnvironmentObject private var wellnessVM: WellnessViewModel
    @EnvironmentObject private var partnerVM:  PartnerViewModel

    @State private var tabIndex      = 0
    @State private var showPairEntry = false
    @State private var showBreakGlass = false

    private let tabs: [NavTabItem] = [
        NavTabItem(label: "Home",     icon: "house.fill"),
        NavTabItem(label: "Progress", icon: "chart.line.uptrend.xyaxis"),
        NavTabItem(label: "Activity", icon: "list.bullet.rectangle"),
        NavTabItem(label: "Profile",  icon: "person.fill"),
    ]

    var body: some View {
        Color.paper.ignoresSafeArea()
            .overlay(
                Group {
                    switch tabIndex {
                    case 0: UserHomeTab(isPaired: isPaired, showBreakGlass: $showBreakGlass)
                    case 1: UserProgressTab()
                    case 2: UserActivityTab()
                    default: UserProfileTab()
                    }
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppBottomNav(tabs: tabs, selection: $tabIndex)
                    .padding(.bottom, 8)
                    .background(Color.paper)
            }
            .sheet(isPresented: $showPairEntry)  { NavigationStack { PairCodeEntryView() } }
            .sheet(isPresented: $showBreakGlass) { EmergencyOverrideView() }
            .onAppear {
                if auth.consumeOpenPairCodeOnUserDashboard() { showPairEntry = true }
            }
    }
}

// MARK: - Home Tab

private struct UserHomeTab: View {
    let isPaired: Bool
    @Binding var showBreakGlass: Bool

    @EnvironmentObject private var activityVM: ActivityViewModel
    @EnvironmentObject private var wellnessVM: WellnessViewModel
    @EnvironmentObject private var partnerVM:  PartnerViewModel
    @ObservedObject private var hk = HealthKitService.shared

    private var remaining: Int {
        max(0, Int(activityVM.activityGoal.agreedTarget - activityVM.activityGoal.currentProgress))
    }

    private var heartRateDisplay: String {
        if hk.heartRateLatest > 0 { return "\(Int(hk.heartRateLatest))" }
        if wellnessVM.rhr > 0     { return "\(Int(wellnessVM.rhr))" }
        return "—"
    }
    private var heartRateSub: String { hk.heartRateLatest > 0 ? "current" : "resting" }
    private var sleepValue: String {
        let h = wellnessVM.sleepDuration / 60
        return h > 0 ? String(format: "%.1f", h) : "—"
    }
    private var sleepUnit: String { wellnessVM.sleepDuration > 0 ? "hrs" : "" }
    private var sleepSub: String { wellnessVM.sleepDuration > 0 ? "last night" : "no data" }
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {

                // Header — same structure as Solo, badge differs
                AppDashHeader(
                    greeting: "Welcome back",
                    name:     AuthManager.shared.userDisplayName,
                    badge: isPaired ? AppDashBadge(
                        text: "Monitored",
                        textColor: .deepTeal,
                        bg: Color.deepTeal.opacity(0.1),
                        dot: .emeraldGreen
                    ) : nil
                )
                .padding(.horizontal, 20)
                .padding(.top, 56)

                // Pairing prompt if not paired
                if !isPaired {
                    UserPairPrompt()
                        .padding(.horizontal, 20)
                }

                // Monitor identity strip (only when paired)
                if isPaired && !partnerVM.partnerDisplayName.isEmpty {
                    UserMonitorStrip(partnerName: partnerVM.partnerDisplayName)
                        .padding(.horizontal, 20)
                }

                // Shield banner — identical component to Solo
                AppShieldBanner(locked: !activityVM.isUnlocked, remaining: remaining)
                    .padding(.horizontal, 20)

                if hk.allTypesDenied {
                    HealthKitDeniedBanner()
                        .padding(.horizontal, 20)
                }

                // Hero card — same component; extra content = "goal set by" badge
                AppHeroCard(
                    calories: Int(activityVM.activityGoal.currentProgress),
                    steps:    activityVM.stepsToday,
                    fraction: activityVM.activityGoal.progressFraction,
                    locked:   !activityVM.isUnlocked,
                    extraContent: isPaired ? AnyView(UserGoalSetBadge(name: partnerVM.partnerDisplayName)) : nil
                )
                .padding(.horizontal, 20)

                // 2 × 2 stat tiles — same component as Solo, live HK data
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    AppPastelTile(bg: .pasteLavender, icon: "heart.fill", iconColor: Color(hex: "#A897FF"),
                                  label: "Heart Rate",
                                  value: heartRateDisplay, unit: "bpm", sub: heartRateSub)
                    AppPastelTile(bg: .pasteMint, icon: "figure.run", iconColor: Color(hex: "#34C99A"),
                                  label: "Active",
                                  value: "\(activeMin)", unit: "min", sub: "of 45 goal")
                    AppPastelTile(bg: .pastePeach, icon: "moon.fill", iconColor: Color(hex: "#FF9B85"),
                                  label: "Sleep",
                                  value: sleepValue, unit: sleepUnit, sub: sleepSub)
                    AppPastelTile(bg: .pasteYellow, icon: "bolt.fill", iconColor: Color(hex: "#E6A800"),
                                  label: "Energy",
                                  value: energyValue, unit: energyUnit, sub: energySub)
                }
                .padding(.horizontal, 20)

                // Weekly achievements — real HealthKit-driven progress, replaces
                // the old hardcoded stat strip.
                WeeklyAchievementsCard(
                    calorieHistory: hk.calorieHistory,
                    dailyGoal:      activityVM.activityGoal.agreedTarget
                )
                .padding(.horizontal, 20)

                // Biometrics — same component
                DashSectionHeader(title: "Biometrics").padding(.horizontal, 20)
                AppBiometricStrip(hrv: wellnessVM.hrv, rhr: wellnessVM.rhr, resp: wellnessVM.respiratoryRate)
                    .padding(.horizontal, 20)

                // Recent activity
                if isPaired {
                    DashSectionHeader(title: "What your monitor sees").padding(.horizontal, 20)
                    UserRecentActivity(events: partnerVM.auditLog)
                        .padding(.horizontal, 20)
                }

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

    private var activeMin: Int { Int(activityVM.activityGoal.progressFraction * 45) }
}

// MARK: - User-specific subviews

private struct UserPairPrompt: View {
    @State private var showEntry = false
    var body: some View {
        DashCard {
            HStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 18)).foregroundColor(.electricOrange)
                Text("Enter your monitor's 6-digit code to finish pairing.")
                    .font(.system(size: 13)).foregroundColor(.ink)
                    .lineLimit(2)
                Spacer()
                Button("Link") { showEntry = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.electricOrange)
            }
        }
        .sheet(isPresented: $showEntry) { NavigationStack { PairCodeEntryView() } }
    }
}

private struct UserMonitorStrip: View {
    let partnerName: String
    var body: some View {
        DashCard(padding: .init(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.deepTeal)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(String(partnerName.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        )
                    Circle().fill(Color.emeraldGreen).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Color.cardWhite, lineWidth: 1.5))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("YOUR MONITOR")
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.muted).tracking(0.8)
                    Text(partnerName)
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.ink)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.emeraldGreen).frame(width: 6, height: 6)
                    Text("Live").font(.system(size: 10, weight: .semibold)).foregroundColor(.emeraldGreen)
                }
            }
        }
    }
}

private struct UserGoalSetBadge: View {
    let name: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.fill.checkmark").font(.system(size: 10))
            Text("Goal set by \(name)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color.white.opacity(0.7))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}

private struct UserRecentActivity: View {
    let events: [AuditEvent]
    var body: some View {
        DashCard(padding: .init(top: 16, leading: 0, bottom: 4, trailing: 0)) {
            VStack(spacing: 0) {
                if events.isEmpty {
                    Text("No recent events")
                        .font(.system(size: 13)).foregroundColor(.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 18).padding(.bottom, 12)
                } else {
                    ForEach(events.prefix(3).indices, id: \.self) { i in
                        let e = events[i]
                        AppAuditRow(
                            dot:    auditDotColor(e.eventType),
                            title:  e.eventType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                            detail: e.agentDisplayName,
                            time:   relativeTimeString(e.timestamp),
                            isLast: i == min(2, events.count - 1)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Progress Tab

private struct UserProgressTab: View {
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

// MARK: - Activity Tab

private struct UserActivityTab: View {
    @EnvironmentObject private var partnerVM: PartnerViewModel
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Text("ACTIVITY")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.muted).tracking(0.8)
                    .padding(.top, 72)
                DashCard(padding: .init(top: 16, leading: 0, bottom: 4, trailing: 0)) {
                    VStack(spacing: 0) {
                        if partnerVM.auditLog.isEmpty {
                            Text("No events yet")
                                .font(.system(size: 13)).foregroundColor(.muted)
                                .padding(18)
                        } else {
                            ForEach(partnerVM.auditLog.indices, id: \.self) { i in
                                let e = partnerVM.auditLog[i]
                                AppAuditRow(
                                    dot:    auditDotColor(e.eventType),
                                    title:  e.eventType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                                    detail: e.agentDisplayName,
                                    time:   relativeTimeString(e.timestamp),
                                    isLast: i == partnerVM.auditLog.count - 1
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Profile Tab

private struct UserProfileTab: View {
    @EnvironmentObject private var activityVM: ActivityViewModel
    @EnvironmentObject private var partnerVM: PartnerViewModel
    @ObservedObject private var screenTime = ScreenTimeService.shared
    @ObservedObject private var hk = HealthKitService.shared
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
            modeLabel:            "Monitored Mode",
            modeColor:            .deepTeal,
            dailyGoal:            Int(activityVM.activityGoal.agreedTarget),
            appsBlocked:          totalApps,
            isPaired:             partnerVM.isPartnerPaired,
            bodyMetricsSummary:   bodyMetricsSummaryLine,
            onEditBodyMetrics:    { showBodyMetricsSheet = true }
        )
        .onAppear {
            Task { try? await hk.fetchUserProfile() }
        }
        .sheet(isPresented: $showBodyMetricsSheet) {
            BodyMetricsEditorSheet()
                .environmentObject(activityVM)
        }
    }
}
