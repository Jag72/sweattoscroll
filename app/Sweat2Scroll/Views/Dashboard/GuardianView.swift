// Views/Dashboard/GuardianView.swift — PRD §6C / §4A guardian/rules tab
// Full rules & settings control panel for Monitor mode.
// Rendered as tab index 2 inside MonitorDashboardView — no internal nav bar.

import SwiftUI

struct GuardianView: View {
    @ObservedObject private var auth = AuthManager.shared
    @EnvironmentObject private var partnerVM: PartnerViewModel

    @State private var sheet: GuardianSheet? = nil
    @State private var rules = GuardianRules()
    @State private var notifs = GuardianNotifs()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                // Page title — matches the .padding(.top, 72) rhythm of other tabs
                VStack(alignment: .leading, spacing: 2) {
                    Text("RULES & SETTINGS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.muted)
                        .tracking(0.8)
                    Text("Guardian Panel")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(.ink)
                    Text("You control what your partner needs to do.")
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 72)

                // Partner section
                GuardianSection(label: "PARTNER") {
                    PartnerCard(isPaired: isPaired, partnerName: partnerVM.partnerDisplayName)
                    if isPaired {
                        ChevronRow(label: "Generate Pairing Code",
                                   sub: "Share to re-link your partner's account") {
                            sheet = .totp
                        }
                    } else {
                        Button {
                            sheet = .totp
                        } label: {
                            Text("+ Pair a Partner")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.deepTeal))
                        }
                        .padding(.horizontal, 4).padding(.bottom, 4)
                    }
                }

                // Goal Rules
                GuardianSection(label: "GOAL RULES") {
                    ChevronRow(label: "Daily Calorie Goal", value: "300 kcal") {}
                    ChevronRow(label: "Step Goal", value: "Off",
                               badge: GuardianBadge(text: "OFF", bg: Color.muted.opacity(0.12), color: .muted)) {}
                    ChevronRow(label: "Active Minutes Goal", value: "Off",
                               badge: GuardianBadge(text: "OFF", bg: Color.muted.opacity(0.12), color: .muted),
                               isLast: true) {}
                }

                // Schedule
                GuardianSection(label: "SCHEDULE") {
                    ChevronRow(label: "Active Days", sub: "Mon–Fri enforced") { sheet = .schedule }
                    ToggleRow(label: "Weekends Off", sub: "No enforcement Sat & Sun",
                              isOn: $rules.weekendsOff, accent: .deepTeal)
                    ToggleRow(label: "Grace Period", sub: "Allow 30 min delay in HealthKit data",
                              isOn: $rules.gracePeriod, accent: .deepTeal, isLast: true)
                }

                // Override Policy
                GuardianSection(label: "OVERRIDE POLICY") {
                    ToggleRow(label: "Allow Break-Glass",
                              sub: "Partner can request emergency 15-min access",
                              isOn: $rules.allowBypass, accent: .amber)
                    ToggleRow(label: "Require Approval",
                              sub: "You must approve all override requests",
                              isOn: $rules.requireApproval, accent: .deepTeal)
                    ToggleRow(label: "Strict Mode",
                              sub: "No overrides under any circumstance",
                              isOn: $rules.strict, accent: .rose, isLast: true)
                }

                if rules.strict {
                    Text("Strict mode is on — your partner cannot request any overrides.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.rose)
                        .padding(.horizontal, 24)
                        .padding(.top, -14)
                }

                // Notifications
                GuardianSection(label: "NOTIFICATIONS") {
                    ToggleRow(label: "Goal met", sub: "When partner hits their daily goal",
                              isOn: $notifs.goalMet, accent: .emeraldGreen)
                    ToggleRow(label: "Goal missed", sub: "End-of-day if goal not reached",
                              isOn: $notifs.goalMissed, accent: .amber)
                    ToggleRow(label: "Override requests", sub: "Immediate push notification",
                              isOn: $notifs.bypass, accent: .rose)
                    ToggleRow(label: "Tamper alerts", sub: "HealthKit revoked, clock drift",
                              isOn: $notifs.tamper, accent: .rose, isLast: true)
                }

                // Security
                GuardianSection(label: "SECURITY") {
                    ChevronRow(label: "Audit Log", sub: "All events, encrypted in CloudKit") {
                        sheet = .auditLog
                    }
                    ChevronRow(label: "Rotate TOTP Secret",
                               sub: "Invalidates old codes immediately", isLast: true) {}
                }

                // Danger Zone
                GuardianSection(label: "DANGER ZONE") {
                    ChevronRow(label: "Unpair Account",
                               sub: "Removes all monitoring rules",
                               labelColor: .rose, isLast: true) {}
                }
                Text("This action cannot be undone.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.rose)
                    .padding(.horizontal, 24).padding(.top, -14)
            }
            .padding(.bottom, 16)
        }
        .background(Color.paper.ignoresSafeArea())
        .sheet(item: $sheet) { s in
            switch s {
            case .totp:     NavigationStack { PairCodeGeneratorView() }
            case .schedule: ScheduleSheet()
            case .auditLog: NavigationStack { AuditLogView() }
            }
        }
    }

    private var isPaired: Bool {
        if case .monitor(let p) = auth.authState { return p }
        return false
    }
}

// MARK: - Sheet enum

private enum GuardianSheet: Identifiable {
    case totp, schedule, auditLog
    var id: String {
        switch self { case .totp: return "totp"; case .schedule: return "schedule"; case .auditLog: return "audit" }
    }
}

// MARK: - Rule / notif state

private struct GuardianRules {
    var weekendsOff     = false
    var gracePeriod     = true
    var allowBypass     = true
    var requireApproval = true
    var strict          = false
}

private struct GuardianNotifs {
    var goalMet    = true
    var goalMissed = true
    var bypass     = true
    var tamper     = true
}

// MARK: - Section wrapper

private struct GuardianSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.muted)
                .tracking(1.4)
                .padding(.horizontal, 24)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Row Components

private struct GuardianBadge {
    let text: String; let bg: Color; let color: Color
}

private struct ChevronRow: View {
    let label: String
    var sub: String? = nil
    var value: String? = nil
    var badge: GuardianBadge? = nil
    var labelColor: Color = .ink
    var isLast: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(labelColor)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundColor(.muted)
                    }
                }
                Spacer()
                if let badge {
                    Text(badge.text)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(badge.color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 8).fill(badge.bg))
                }
                if let value {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.muted)
                        .padding(.trailing, 4)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.18))
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        if !isLast {
            Divider().padding(.leading, 16)
        }
    }
}

private struct ToggleRow: View {
    let label: String
    var sub: String? = nil
    @Binding var isOn: Bool
    let accent: Color
    var isLast: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.ink)
                if let sub {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundColor(.muted)
                }
            }
            Spacer()
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isOn ? accent : Color.muted.opacity(0.25))
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(3)
            }
            .animation(.easeInOut(duration: 0.2), value: isOn)
            .onTapGesture { isOn.toggle() }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        if !isLast {
            Divider().padding(.leading, 16)
        }
    }
}

// MARK: - Partner card

private struct PartnerCard: View {
    let isPaired: Bool
    let partnerName: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(isPaired ? String(partnerName.prefix(1)).uppercased() : "?")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(.white)
                    )
                Circle()
                    .fill(isPaired ? Color.emeraldGreen : Color.amber)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.heroGradientBottom, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isPaired ? "PAIRED ACCOUNT" : "NO PARTNER")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(0.8)
                Text(isPaired ? (partnerName.isEmpty ? "Partner" : partnerName) : "Add a partner")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                if isPaired {
                    Text("Paired 6 days ago · CloudKit active")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            Spacer()
            if isPaired {
                Text("ACTIVE")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white)
                    .tracking(0.5)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.heroGradientTop, Color.heroGradientBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Schedule Sheet

private struct ScheduleSheet: View {
    @State private var days: [String: Bool] = [
        "M": true, "T": true, "W": true, "Th": true, "F": true, "Sa": false, "Su": false
    ]
    @State private var grace: Double = 30
    @Environment(\.dismiss) private var dismiss

    private let dayOrder = ["M", "T", "W", "Th", "F", "Sa", "Su"]

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(Color.muted.opacity(0.3))
                .frame(width: 36, height: 5).padding(.top, 16).padding(.bottom, 24)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schedule")
                            .font(.system(size: 22, weight: .black)).foregroundColor(.ink)
                        Text("Which days should the goal apply?")
                            .font(.system(size: 13)).foregroundColor(.muted)
                    }

                    // Day pills
                    HStack(spacing: 6) {
                        ForEach(dayOrder, id: \.self) { d in
                            let on = days[d] ?? false
                            Button { days[d] = !(days[d] ?? false) } label: {
                                Text(d)
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundColor(on ? .white : .muted)
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(on ? Color.deepTeal : Color.paper))
                            }
                        }
                    }

                    // Grace period slider
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Grace Period")
                                    .font(.system(size: 14, weight: .heavy)).foregroundColor(.ink)
                                Text("Allow access if HealthKit data is delayed")
                                    .font(.system(size: 11)).foregroundColor(.muted)
                            }
                            Spacer()
                            Text("\(Int(grace))m")
                                .font(.system(size: 20, weight: .black)).foregroundColor(.deepTeal)
                        }
                        Slider(value: $grace, in: 5...120, step: 5).tint(.deepTeal)
                        HStack {
                            Text("5 min").font(.system(size: 10)).foregroundColor(.muted)
                            Spacer()
                            Text("2 hrs").font(.system(size: 10)).foregroundColor(.muted)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16).fill(Color.paper)
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                    )

                    Button { dismiss() } label: {
                        Text("Save Schedule")
                            .font(.system(size: 15, weight: .heavy)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.deepTeal))
                    }
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.paper))
                    }
                }
                .padding(20)
            }
        }
        .background(Color.cardWhite)
        .presentationDetents([.large])
    }
}
