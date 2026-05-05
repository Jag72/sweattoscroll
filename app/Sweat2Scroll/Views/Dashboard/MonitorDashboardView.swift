// Views/Dashboard/MonitorDashboardView.swift
// Monitor mode — same visual language, control-panel content.

import SwiftUI

struct MonitorDashboardView: View {
    let isPaired: Bool

    @ObservedObject private var auth = AuthManager.shared
    @EnvironmentObject private var partnerVM:  PartnerViewModel
    @EnvironmentObject private var wellnessVM: WellnessViewModel

    @State private var tabIndex    = 0
    @State private var showGoalEdit = false
    @State private var showOverride = false

    private let tabs: [NavTabItem] = [
        NavTabItem(label: "Home",    icon: "house.fill"),
        NavTabItem(label: "Partner", icon: "person.2.fill"),
        NavTabItem(label: "Rules",   icon: "checkmark.shield.fill"),
        NavTabItem(label: "Profile", icon: "person.fill"),
    ]

    var body: some View {
        Color.paper.ignoresSafeArea()
            .overlay(
                Group {
                    switch tabIndex {
                    case 0: MonitorHomeTab(isPaired: isPaired,
                                           showGoalEdit: $showGoalEdit,
                                           showOverride: $showOverride)
                    case 1: MonitorPartnerTab()
                    case 2: GuardianView()
                    default: MonitorProfileTab()
                    }
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppBottomNav(tabs: tabs, selection: $tabIndex)
                    .padding(.bottom, 8)
                    .background(Color.paper)
            }
            .sheet(isPresented: $showGoalEdit) {
                MonitorGoalSheet(currentGoal: partnerVM.partnerGoal)
            }
            .sheet(isPresented: $showOverride) {
                EmergencyOverrideView()
            }
    }
}

// MARK: - Home Tab

private struct MonitorHomeTab: View {
    let isPaired: Bool
    @Binding var showGoalEdit: Bool
    @Binding var showOverride: Bool

    @EnvironmentObject private var partnerVM:  PartnerViewModel
    @EnvironmentObject private var wellnessVM: WellnessViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {

                // Header — "COACH" badge instead of streak
                AppDashHeader(
                    greeting: "Monitor Panel",
                    name:     AuthManager.shared.userDisplayName,
                    badge: AppDashBadge(
                        text: "Coach",
                        textColor: .deepTeal,
                        bg: Color.deepTeal.opacity(0.1),
                        dot: .emeraldGreen
                    )
                )
                .padding(.horizontal, 20)
                .padding(.top, 56)

                // Bypass approval (when pending)
                if partnerVM.hasPendingBypassRequest {
                    MonitorBypassCard(name: partnerVM.partnerDisplayName)
                        .padding(.horizontal, 20)
                }

                // Partner status card (or unpaired prompt)
                if isPaired {
                    // Shield banner reads partner's state
                    AppShieldBanner(
                        locked:    partnerVM.partnerCalories < partnerVM.partnerGoal,
                        remaining: max(0, Int(partnerVM.partnerGoal - partnerVM.partnerCalories))
                    )
                    .padding(.horizontal, 20)

                    // Hero card shows partner's data
                    AppHeroCard(
                        calories: Int(partnerVM.partnerCalories),
                        steps:    partnerVM.partnerSteps,
                        fraction: partnerVM.partnerProgressFraction,
                        locked:   partnerVM.partnerCalories < partnerVM.partnerGoal,
                        extraContent: AnyView(
                            MonitoringLabel(name: partnerVM.partnerDisplayName)
                        )
                    )
                    .padding(.horizontal, 20)

                    // Goal row
                    MonitorGoalRow(goal: partnerVM.partnerGoal, onEdit: { showGoalEdit = true })
                        .padding(.horizontal, 20)

                    // Send override OTP — primary action for the controller role
                    MonitorOverrideCard(
                        partnerName: partnerVM.partnerDisplayName,
                        action: { showOverride = true }
                    )
                    .padding(.horizontal, 20)

                    // Partner wellness
                    DashSectionHeader(title: "\(partnerVM.partnerDisplayName.isEmpty ? "Partner" : partnerVM.partnerDisplayName)'s Wellness")
                        .padding(.horizontal, 20)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        AppPastelTile(bg: .pasteLavender, icon: "waveform.path.ecg", iconColor: Color(hex: "#A897FF"),
                                      label: "HRV", value: String(format: "%.0f", wellnessVM.hrv), unit: "ms", sub: "")
                        AppPastelTile(bg: .pasteMint, icon: "heart.fill", iconColor: Color(hex: "#34C99A"),
                                      label: "Resting HR", value: String(format: "%.0f", wellnessVM.rhr), unit: "bpm", sub: "")
                        AppPastelTile(bg: .pastePeach, icon: "moon.fill", iconColor: Color(hex: "#FF9B85"),
                                      label: "Sleep", value: String(format: "%.1f", wellnessVM.sleepDuration / 60), unit: "hrs", sub: "")
                        AppPastelTile(bg: .pasteYellow, icon: "lungs.fill", iconColor: Color(hex: "#E6A800"),
                                      label: "Resp Rate", value: String(format: "%.0f", wellnessVM.respiratoryRate), unit: "/min", sub: "")
                    }
                    .padding(.horizontal, 20)

                    // Week chart — partner's weekly goal completions when shared via CloudKit;
                    // shows neutral empty state until partner data arrives.
                    DashSectionHeader(title: "This Week").padding(.horizontal, 20)
                    AppWeekChart(
                        completions: Array(repeating: false, count: 7),
                        todayIndex:  6
                    )
                    .padding(.horizontal, 20)

                    // Activity log
                    DashSectionHeader(title: "Activity Log").padding(.horizontal, 20)
                    MonitorActivityLog(events: partnerVM.auditLog).padding(.horizontal, 20)

                } else {
                    MonitorUnpairedCard().padding(.horizontal, 20)
                }

                Spacer(minLength: 16)
            }
            .padding(.bottom, 16)
        }
        .task {
            await wellnessVM.loadLiveData()
        }
        .refreshable {
            await wellnessVM.loadLiveData()
        }
    }
}

// MARK: - Monitor-specific subviews

private struct MonitoringLabel: View {
    let name: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "eye.fill").font(.system(size: 10))
            Text("Monitoring \(name.isEmpty ? "partner" : name)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.65))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}

private struct MonitorBypassCard: View {
    let name: String
    @State private var decided: Bool? = nil

    var body: some View {
        DashCard {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.amber.opacity(0.15)).frame(width: 36, height: 36)
                        Image(systemName: "bolt.fill").font(.system(size: 14)).foregroundColor(.amber)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Override Request")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.ink)
                        Text("\(name.isEmpty ? "Your partner" : name) needs emergency access — 15 min")
                            .font(.system(size: 12)).foregroundColor(.muted)
                    }
                    Spacer()
                }
                if let d = decided {
                    Text(d ? "Access granted for 15 minutes" : "Request denied")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(d ? .emeraldGreen : .rose)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack(spacing: 8) {
                        Button { decided = true } label: {
                            Text("Approve").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.emeraldGreen))
                        }
                        Button { decided = false } label: {
                            Text("Deny").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.rose))
                        }
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.amber.opacity(0.3), lineWidth: 1.5)
        )
    }
}

private struct MonitorOverrideCard: View {
    let partnerName: String
    let action: () -> Void

    private var nameDisplay: String {
        partnerName.isEmpty ? "your partner" : partnerName
    }

    var body: some View {
        DashCard(padding: .init(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.electricOrange.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "key.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.electricOrange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EMERGENCY OVERRIDE")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.muted).tracking(0.8)
                        Text("Send an OTP to \(nameDisplay)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.ink)
                    }
                    Spacer()
                }
                Text("Pick a duration and generate a 6-digit code. They type it in to unlock their apps for that long.")
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
                Button(action: action) {
                    Text("Send override code")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.electricOrange)
                        )
                }
            }
        }
    }
}

private struct MonitorGoalRow: View {
    let goal: Double
    let onEdit: () -> Void
    var body: some View {
        DashCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.electricOrange.opacity(0.1)).frame(width: 40, height: 40)
                    Image(systemName: "target").font(.system(size: 18)).foregroundColor(.electricOrange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAILY GOAL").font(.system(size: 9, weight: .semibold)).foregroundColor(.muted).tracking(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(goal))").font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(.ink)
                        Text("kcal").font(.system(size: 12, weight: .medium)).foregroundColor(.muted)
                    }
                }
                Spacer()
                Button(action: onEdit) {
                    Text("Edit")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.electricOrange))
                }
            }
        }
    }
}

private struct MonitorUnpairedCard: View {
    @State private var showGen = false
    var body: some View {
        DashCard {
            VStack(spacing: 16) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 40)).foregroundColor(.muted.opacity(0.4))
                VStack(spacing: 4) {
                    Text("No partner linked").font(.system(size: 18, weight: .bold)).foregroundColor(.ink)
                    Text("Generate a pairing code and share it with the person you want to monitor.")
                        .font(.system(size: 13)).foregroundColor(.muted).multilineTextAlignment(.center)
                }
                Button { showGen = true } label: {
                    Text("Generate Pairing Code")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.electricOrange))
                }
            }
        }
        .sheet(isPresented: $showGen) { NavigationStack { PairCodeGeneratorView() } }
    }
}

private struct MonitorActivityLog: View {
    let events: [AuditEvent]
    private let sample: [(Color, String, String, String)] = [
        (.electricOrange, "Workout ended",     "Running · 34 min · 174 kcal", "2h ago"),
        (.emeraldGreen,   "Shield disengaged", "Daily goal reached",           "Yesterday"),
        (.rose,           "Shield engaged",    "Day reset · 0 kcal",           "Yesterday"),
        (.emeraldGreen,   "Goal met",          "312 kcal burned",              "2 days ago"),
        (.muted,          "Goal missed",       "198 / 300 kcal",               "3 days ago"),
    ]
    var body: some View {
        DashCard(padding: .init(top: 4, leading: 0, bottom: 4, trailing: 0)) {
            VStack(spacing: 0) {
                if events.isEmpty {
                    ForEach(sample.indices, id: \.self) { i in
                        let (dot, title, detail, time) = sample[i]
                        AppAuditRow(dot: dot, title: title, detail: detail, time: time, isLast: i == sample.count - 1)
                    }
                } else {
                    ForEach(events.prefix(5).indices, id: \.self) { i in
                        let e = events[i]
                        AppAuditRow(
                            dot:    auditDotColor(e.eventType),
                            title:  e.eventType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                            detail: e.agentDisplayName,
                            time:   relativeTimeString(e.timestamp),
                            isLast: i == min(4, events.count - 1)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Partner tab (detailed partner view)

private struct MonitorPartnerTab: View {
    @EnvironmentObject private var partnerVM: PartnerViewModel
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Text("PARTNER")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.muted).tracking(0.8)
                    .padding(.top, 72)
                RecoveryRingView(
                    fraction: partnerVM.partnerProgressFraction,
                    value: "\(Int(partnerVM.partnerProgressFraction * 100))",
                    unit: "%",
                    label: "PARTNER GOAL",
                    color: partnerVM.partnerCalories >= partnerVM.partnerGoal ? .emeraldGreen : .electricOrange
                )
                AppWeekChart(completions: [true, true, false, true, false, true, false], todayIndex: 6)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Profile Tab

private struct MonitorProfileTab: View {
    @EnvironmentObject private var partnerVM: PartnerViewModel

    var body: some View {
        ProfileScreen(
            modeLabel:    "Monitor Mode",
            modeColor:    .deepTeal,
            dailyGoal:    Int(partnerVM.partnerGoal),
            appsBlocked:  0,
            isPaired:     partnerVM.isPartnerPaired
        )
    }
}

// MARK: - Goal Edit Sheet

struct MonitorGoalSheet: View {
    let currentGoal: Double
    @State private var goal: Double
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var partnerVM: PartnerViewModel

    init(currentGoal: Double) {
        self.currentGoal = currentGoal
        _goal = State(initialValue: currentGoal)
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(Color.muted.opacity(0.3))
                .frame(width: 36, height: 5).padding(.top, 16).padding(.bottom, 24)

            Text("Set Daily Goal").font(.system(size: 22, weight: .bold)).foregroundColor(.ink)
            Text("Partner must hit this to unlock their apps.")
                .font(.system(size: 13)).foregroundColor(.muted).padding(.top, 4).padding(.bottom, 24)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(goal))")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(.electricOrange)
                    .animation(.none, value: goal)
                Text("kcal").font(.system(size: 22, weight: .medium)).foregroundColor(.muted)
            }
            .padding(.bottom, 20)

            Slider(value: $goal, in: 100...600, step: 25)
                .tint(Color.electricOrange).padding(.horizontal, 20)
            HStack {
                Text("100").font(.system(size: 10)).foregroundColor(.muted)
                Spacer()
                Text("600 kcal").font(.system(size: 10)).foregroundColor(.muted)
            }
            .padding(.horizontal, 20).padding(.bottom, 20)

            HStack(spacing: 8) {
                ForEach([200, 250, 300, 350, 400], id: \.self) { v in
                    Button { goal = Double(v) } label: {
                        Text("\(v)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Int(goal) == v ? .white : .muted)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Int(goal) == v ? Color.electricOrange : Color.clear)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Int(goal) == v ? Color.electricOrange : Color.muted.opacity(0.3), lineWidth: 1.5))
                            )
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 28)

            Button {
                partnerVM.partnerGoal = goal
                dismiss()
            } label: {
                Text("Save Goal").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.electricOrange))
            }
            .padding(.horizontal, 20).padding(.bottom, 10)

            Button { dismiss() } label: {
                Text("Cancel").font(.system(size: 14, weight: .medium)).foregroundColor(.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.ringTrack))
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .background(Color.white)
        .presentationDetents([.large])
    }
}

// MARK: - PartnerViewModel extension

private extension PartnerViewModel {
    var hasPendingBypassRequest: Bool { false }
}
