// Views/Dashboard/DashboardShared.swift
// Unified design tokens, nav bar, and shared components for all three mode dashboards.
// One theme, one nav, one card language — differentiation is content-only.

import SwiftUI
import UIKit

// MARK: - HealthKit Permissions Banner

/// Shown on every dashboard when iOS is reporting that the user has denied
/// every HealthKit read type — typically because they revoked access in
/// Settings → Health → Data Access. Tapping the CTA opens the Health app
/// directly to the device's source list.
struct HealthKitDeniedBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.rose)
                Text("Apple Health is blocking us. Open Settings → Health → Data Access & Devices → Sweat2Scroll and turn the categories on.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.leading)
            }
            Button {
                if let url = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(url)
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Health settings")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.rose)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.rose.opacity(0.10))
        )
    }
}

// MARK: - Unified Color Palette

extension Color {
    // App brand palette — single source of truth used across all views
    static let electricOrange = Color(red: 1.0,   green: 0.388, blue: 0.129) // #FF6321 — primary CTA, nav active, progress rings
    static let deepTeal       = Color(red: 0.059, green: 0.298, blue: 0.361) // #0F4C5C — monitor mode accents, teal badges
    static let paper          = Color(red: 0.961, green: 0.949, blue: 0.929) // #F5F2ED — all dashboard backgrounds
    static let ink            = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A — primary text
    static let muted          = Color(red: 0.557, green: 0.557, blue: 0.557) // #8E8E8E — labels and sub-text
    static let emeraldGreen   = Color(red: 0.180, green: 0.800, blue: 0.443) // #2ECC71 — unlocked / positive states
    static let rose           = Color(red: 1.0,   green: 0.353, blue: 0.529) // #FF5A87 — locked / alert states
    static let amber          = Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B — warnings / near-goal
    static let ringTrack      = Color(red: 0.894, green: 0.894, blue: 0.906) // #E4E4E7 — unfilled progress rings, dividers

    static let heroGradientTop    = Color(red: 0.11, green: 0.23, blue: 0.29)   // #1C3A4A
    static let heroGradientBottom = Color(red: 0.06, green: 0.13, blue: 0.19)   // #0F2030
    static let cardWhite          = Color.white
    static let navSurface         = Color(red: 0.067, green: 0.067, blue: 0.067) // #111

    // Pastel tile backgrounds (same across all modes)
    static let pasteLavender = Color(red: 0.918, green: 0.902, blue: 1.0)    // #EAE6FF
    static let pasteMint     = Color(red: 0.824, green: 0.961, blue: 0.925)  // #D2F5EC
    static let pastePeach    = Color(red: 1.0,   green: 0.910, blue: 0.886)  // #FFE8E3
    static let pasteYellow   = Color(red: 1.0,   green: 0.957, blue: 0.800)  // #FFF4CC

    /// Initialize a Color from a hex string. Accepts "#RGB", "#RRGGBB", or "#AARRGGBB"
    /// (with or without the leading `#`). Falls back to opaque black on malformed input.
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)

        let a, r, g, b: UInt64
        switch trimmed.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255,
                            (value >> 8 & 0xF) * 17,
                            (value >> 4 & 0xF) * 17,
                            (value      & 0xF) * 17)
        case 6: // RRGGBB (24-bit)
            (a, r, g, b) = (255,
                            value >> 16 & 0xFF,
                            value >> 8  & 0xFF,
                            value       & 0xFF)
        case 8: // AARRGGBB (32-bit)
            (a, r, g, b) = (value >> 24 & 0xFF,
                            value >> 16 & 0xFF,
                            value >> 8  & 0xFF,
                            value       & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red:   Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Unified Bottom Nav Bar

/// Single nav bar used by all three mode dashboards.
/// Pass the tab enum (via AnyDashboardTab protocol) and an orange active indicator.
struct AppBottomNav: View {
    let tabs: [NavTabItem]
    @Binding var selection: Int
    var accent: Color = .electricOrange

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { i in
                let isActive = selection == i
                Button { selection = i } label: {
                    Image(systemName: tabs[i].icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isActive ? Color.navSurface : Color.white.opacity(0.55))
                        .frame(width: 46, height: 46)
                        .background(
                            Circle().fill(isActive ? Color.white : Color.clear)
                        )
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color.navSurface)
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
        )
        .padding(.horizontal, 20)
    }
}

struct NavTabItem {
    let label: String
    let icon: String
}

// MARK: - Unified Card

struct DashCard<Content: View>: View {
    var padding: EdgeInsets = .init(top: 18, leading: 18, bottom: 18, trailing: 18)
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.cardWhite)
                    .shadow(color: .black.opacity(0.045), radius: 10, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.04),  radius: 3,  x: 0, y: 1)
            )
    }
}

// MARK: - Unified Shield Banner

struct AppShieldBanner: View {
    let locked: Bool
    let remaining: Int

    var body: some View {
        let color: Color = locked ? .rose : .emeraldGreen
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(color)
                    .frame(width: 42, height: 42)
                Image(systemName: locked ? "lock.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(locked ? "Apps blocked" : "Goal met — apps unlocked")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.ink)
                Text(locked ? "\(remaining) kcal to go" : "You earned your scroll.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.muted)
            }
            Spacer(minLength: 8)
            if locked {
                Text("\(max(0, 100 - Int(Double(remaining) / max(1, Double(remaining + 10)) * 100)))%")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(color)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.045), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.04),  radius: 3,  x: 0, y: 1)
        )
    }
}

// MARK: - Unified Hero Card (dark gradient)

struct AppHeroCard: View {
    let calories: Int
    let steps: Int
    let fraction: Double
    let locked: Bool
    /// Optional extra content shown between numbers and progress bar
    var extraContent: AnyView? = nil

    @State private var animated: Double = 0

    private var ringColor: Color {
        if !locked { return .emeraldGreen }
        return fraction > 0.75 ? .amber : .electricOrange
    }

    var body: some View {
        VStack(spacing: 0) {
            // Numbers section
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(calories.formatted())")
                                .font(.system(size: 52, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("KCAL")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.bottom, 6)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(steps.formatted())")
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                            Text("STEPS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    Spacer()
                    // Compact arc
                    CompactArcRing(fraction: fraction, color: ringColor, size: 72)
                }

                if let extra = extraContent {
                    extra
                }
            }
            .padding(20)

            // Progress bar
            VStack(spacing: 6) {
                HStack {
                    Text(locked
                         ? "\(max(0, 300 - calories)) kcal remaining"
                         : "Goal complete")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ringColor)
                }
                .padding(.horizontal, 20)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.1))
                        Rectangle()
                            .fill(ringColor)
                            .frame(width: geo.size.width * min(1, animated))
                    }
                }
                .frame(height: 5)
                .animation(.easeOut(duration: 1.2), value: animated)
            }
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [.heroGradientTop, .heroGradientBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { animated = fraction }
        .onChange(of: fraction) { animated = $0 }
    }
}

/// Small arc ring for inside hero card or badges
struct CompactArcRing: View {
    let fraction: Double
    let color: Color
    let size: CGFloat
    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: animated)
            Text("\(Int(fraction * 100))%")
                .font(.system(size: size * 0.22, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .onAppear { animated = fraction }
        .onChange(of: fraction) { animated = $0 }
    }
}

// MARK: - Unified Pastel Stat Tile

struct AppPastelTile: View {
    /// Retained for call-site compatibility. Clean-minimal renders white cards,
    /// so this pastel value is no longer painted as the tile background.
    let bg: Color
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let unit: String
    let sub: String
    /// Optional mini progress ring (0...1) shown top-right in the icon's tint.
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(iconColor)
                Spacer()
                if let p = progress {
                    ZStack {
                        Circle().stroke(iconColor.opacity(0.15), lineWidth: 3.5)
                        Circle()
                            .trim(from: 0, to: min(max(p, 0), 1))
                            .stroke(iconColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 30, height: 30)
                }
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.muted)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.muted)
                    .lineLimit(1)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.muted.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 130)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.045), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.04),  radius: 3,  x: 0, y: 1)
        )
    }
}

// MARK: - Unified Biometric Strip

struct AppBiometricStrip: View {
    let hrv: Double
    let rhr: Double
    let resp: Double

    var body: some View {
        DashCard {
            HStack(spacing: 0) {
                ForEach([
                    ("HRV", String(format: "%.0f", hrv), "ms"),
                    ("Resting HR", String(format: "%.0f", rhr), "bpm"),
                    ("Resp Rate", String(format: "%.0f", resp), "/min"),
                ].indices, id: \.self) { i in
                    let items = [
                        ("HRV",        String(format: "%.0f", hrv),  "ms"),
                        ("Resting HR", String(format: "%.0f", rhr),  "bpm"),
                        ("Resp Rate",  String(format: "%.0f", resp), "/min"),
                    ]
                    let (label, value, unit) = items[i]
                    VStack(spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(value)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.ink)
                            Text(unit)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.muted)
                        }
                        Text(label.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.muted)
                            .tracking(0.4)
                    }
                    .frame(maxWidth: .infinity)
                    if i < 2 {
                        Divider().frame(height: 32)
                    }
                }
            }
        }
    }
}

// MARK: - Unified Section Header

struct DashSectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.muted)
                .tracking(0.8)
            Spacer()
            if let action, let onAction {
                Button(action: onAction) {
                    Text(action)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.electricOrange)
                }
            }
        }
    }
}

// MARK: - Unified Page Header (name + avatar)

struct AppDashHeader: View {
    let greeting: String
    let name: String
    var badge: AppDashBadge? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.muted)
                Text(name)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.ink)
            }

            Spacer()

            if let badge {
                HStack(spacing: 5) {
                    if let dot = badge.dot {
                        Circle().fill(dot).frame(width: 7, height: 7)
                    }
                    Text(badge.text)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(badge.textColor)
                        .tracking(0.3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(badge.bg)
                )
            }

            // Avatar circle
            Circle()
                .fill(LinearGradient(
                    colors: [.electricOrange, Color(red: 0.91, green: 0.27, blue: 0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                )
        }
    }
}

struct AppDashBadge {
    let text: String
    let textColor: Color
    let bg: Color
    var dot: Color? = nil
}

// MARK: - Unified Week Bar Chart

struct AppWeekChart: View {
    let completions: [Bool]   // 7 values, index 0 = Mon
    let todayIndex: Int

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        DashCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("This Week")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.ink)
                    Spacer()
                    Text("\(completions.filter { $0 }.count) / 7 days")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.electricOrange)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(completions.indices, id: \.self) { i in
                        let done = completions[i]
                        let isToday = i == todayIndex
                        let h = isToday ? 32.0 : (done ? 26.0 : 10.0)
                        let color: Color = isToday ? .electricOrange
                            : done ? .emeraldGreen.opacity(0.6)
                            : .rose.opacity(0.3)
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color)
                                .frame(height: h)
                                .overlay(
                                    isToday ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color.electricOrange, lineWidth: 1.5) : nil
                                )
                            Text(dayLabels[i])
                                .font(.system(size: 9, weight: isToday ? .bold : .medium))
                                .foregroundColor(isToday ? .electricOrange : .muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 50)
            }
        }
    }
}

// MARK: - Unified Activity Feed Row

struct AppAuditRow: View {
    let dot: Color
    let title: String
    let detail: String
    let time: String
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(dot).frame(width: 8, height: 8).padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 1, height: 26)
                        .padding(.top, 3)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.muted)
            }
            Spacer()
            Text(time)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.muted)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, isLast ? 10 : 4)
    }
}

// MARK: - Break-Glass Long-Press Trigger

struct AppBreakGlassTrigger: View {
    @Binding var show: Bool

    var body: some View {
        Button {
            show = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Emergency override")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.rose)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.rose.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

func relativeTimeString(_ date: Date) -> String {
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "just now" }
    if diff < 3600 { return "\(Int(diff / 60))m ago" }
    if diff < 86400 { return "\(Int(diff / 3600))h ago" }
    return "\(Int(diff / 86400))d ago"
}

func auditDotColor(_ type: AuditEventType) -> Color {
    switch type {
    case .calorieUnlock, .stepUnlock, .shieldDisengaged: return .emeraldGreen
    case .shieldEngaged:                                  return .rose
    case .breakGlass, .selfRegBypass:                     return .amber
    case .tamperHealthKit, .tamperScreenTime, .timeDrift: return .rose
    default:                                              return .electricOrange
    }
}

// MARK: - Rich Profile Section

/// Self-contained profile screen used by every dashboard mode. Renders avatar,
/// name, mode chip, daily streak, and a settings list with sign-out at the bottom.
struct ProfileScreen: View {
    let modeLabel: String
    let modeColor: Color
    let dailyGoal: Int
    let appsBlocked: Int
    let isPaired: Bool
    /// Formatted line like `"175 cm · 72 kg · 31 yrs"`. When `nil`, the row is hidden.
    var bodyMetricsSummary: String? = nil
    var onEditBodyMetrics: (() -> Void)? = nil
    var onEditGoal: () -> Void = {}
    var onEditApps: () -> Void = {}
    var onPair: () -> Void = {}
    var onPermissions: () -> Void = {}

    @State private var showSignOutConfirm = false
    @State private var showHelpSupport = false
    @State private var showPrivacyPolicy = false
    @AppStorage("currentStreak") private var streak: Int = 14

    private var displayName: String { AuthManager.shared.userDisplayName }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                profileHeader.padding(.top, 56)

                statsRow

                settingsGroup(title: "Activity") {
                    settingsRow(icon: "flame.fill", color: .electricOrange,
                                title: "Daily calorie goal",
                                value: "\(dailyGoal) kcal", action: onEditGoal)
                    Divider().padding(.leading, 60)
                    settingsRow(icon: "app.badge.checkmark", color: .deepTeal,
                                title: "Restricted apps",
                                value: appsBlocked > 0 ? "\(appsBlocked) blocked" : "None",
                                action: onEditApps)
                }

                if let summary = bodyMetricsSummary, let editBody = onEditBodyMetrics {
                    settingsGroup(title: "Your details") {
                        settingsRow(icon: "heart.text.square.fill", color: .electricOrange,
                                    title: "Height, weight & age",
                                    value: summary, action: editBody)
                    }
                }

                settingsGroup(title: "Accountability") {
                    settingsRow(icon: "person.2.fill", color: .deepTeal,
                                title: "Partner",
                                value: isPaired ? "Connected" : "Not paired",
                                action: onPair)
                    Divider().padding(.leading, 60)
                    settingsRow(icon: "lock.shield.fill", color: .amber,
                                title: "Permissions",
                                value: "Health · Screen Time", action: onPermissions)
                }

                settingsGroup(title: "About") {
                    settingsRow(icon: "questionmark.circle.fill", color: .muted,
                                title: "Help & Support", value: "",
                                action: { showHelpSupport = true })
                    Divider().padding(.leading, 60)
                    settingsRow(icon: "doc.text.fill", color: .muted,
                                title: "Privacy Policy", value: "",
                                action: { showPrivacyPolicy = true })
                    Divider().padding(.leading, 60)
                    settingsRow(icon: "info.circle.fill", color: .muted,
                                title: "Version", value: appVersion, chevron: false)
                }

                Button {
                    showSignOutConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out").fontWeight(.bold)
                    }
                    .foregroundColor(.rose)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.rose.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.rose.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showHelpSupport) { HelpSupportView() }
        .sheet(isPresented: $showPrivacyPolicy) { PrivacyPolicyView() }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) { AuthManager.shared.signOut() }
        } message: {
            Text("You'll need to sign in again to use the app.")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.electricOrange, Color(hex: "#FF7A2A")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.electricOrange.opacity(0.35), radius: 16, y: 6)
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(.ink)
                Text(modeLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(modeColor, in: Capsule())
            }
        }
    }

    private var statsRow: some View {
        DashCard(padding: .init(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            HStack(spacing: 0) {
                statCell(icon: "flame.fill", color: .electricOrange,
                         value: "\(streak)", label: "Day Streak")
                Divider().frame(height: 36)
                statCell(icon: "target", color: .deepTeal,
                         value: "\(dailyGoal)", label: "Daily Goal")
                Divider().frame(height: 36)
                statCell(icon: "shield.fill", color: .amber,
                         value: "\(appsBlocked)", label: "Apps Locked")
            }
        }
        .padding(.horizontal, 20)
    }

    private func statCell(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.muted)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func settingsGroup<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.muted)
                .tracking(0.8)
                .padding(.leading, 24)
            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 2)
                )
                .padding(.horizontal, 20)
        }
    }

    private func settingsRow(icon: String, color: Color, title: String,
                             value: String, chevron: Bool = true,
                             action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.ink)
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.muted)
                }
                if chevron && action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.muted.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - Rich Shield Section

/// Full Shield tab — large status hero, progress bar to goal, blocked-apps preview,
/// quick info, and a long-press break-glass override.
struct ShieldScreen: View {
    let isUnlocked: Bool
    let calories: Int
    let goal: Int
    let appsBlocked: Int
    let blockedAppNames: [String]
    @Binding var showBreakGlass: Bool
    /// When provided, the shield hero adapts copy to the current block-session
    /// phase (monitoring / blocked / bypass15 / dayBypass).
    var blockingPhase: BlockingPhase? = nil
    var exhaustedCount: Int = 0
    var monitoredCount: Int = 0
    var bypassMinutes: Int = 0
    var onTapShield: () -> Void = {}

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(calories) / Double(goal), 1.0)
    }
    private var remaining: Int { max(0, goal - calories) }
    private var accent: Color { isUnlocked ? .emeraldGreen : .electricOrange }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Text("SHIELD")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.muted)
                    .tracking(0.9)
                    .padding(.top, 56)

                shieldHero

                if let phase = blockingPhase {
                    blockingPhaseCard(phase: phase)
                        .padding(.horizontal, 20)
                }

                progressCard

                restrictedAppsSection

                quickStats

                AppBreakGlassTrigger(show: $showBreakGlass)
                    .padding(.horizontal, 20)

                Spacer(minLength: 12)
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func blockingPhaseCard(phase: BlockingPhase) -> some View {
        let copy = blockingPhaseCopy(phase: phase)
        Button {
            if phase == .blocked { onTapShield() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(copy.color.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: copy.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(copy.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.title)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.ink)
                    Text(copy.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                }
                Spacer()
                if phase == .blocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(copy.color)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(copy.color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(copy.color.opacity(0.18), lineWidth: 1.4)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func blockingPhaseCopy(phase: BlockingPhase)
        -> (title: String, subtitle: String, icon: String, color: Color)
    {
        switch phase {
        case .monitoring:
            if exhaustedCount > 0 {
                return ("Per-app scroll limits",
                        "\(exhaustedCount) of \(monitoredCount) locked • 30 min each per day.",
                        "clock.fill", .deepTeal)
            }
            return ("Per-app scroll limits",
                    "30 min per app per day — timer starts when you open each app.",
                    "clock.fill", .deepTeal)
        case .blocked:
            return ("Time to move",
                    "Tap to open the block screen — burn or bypass.",
                    "lock.fill", .rose)
        case .bypass15:
            return ("15-min bypass active",
                    "\(bypassMinutes) min until apps re-lock.",
                    "hourglass", .amber)
        case .dayBypass:
            return ("Day bypass active",
                    "Apps stay open until midnight.",
                    "calendar.badge.exclamationmark", .amber)
        case .unlocked:
            return ("Goal met — apps unlocked",
                    "You earned your scroll.",
                    "checkmark.circle.fill", .emeraldGreen)
        case .idle:
            return ("No apps locked",
                    "Pick apps from Profile → Restricted Apps.",
                    "app.badge", .muted)
        }
    }

    @ViewBuilder
    private var restrictedAppsSection: some View {
        if appsBlocked == 0 {
            DashCard(padding: .init(top: 18, leading: 16, bottom: 18, trailing: 16)) {
                VStack(spacing: 10) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.muted)
                    Text("No apps selected yet")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.ink)
                    Text("Open Profile → Restricted Apps to choose what gets locked.")
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 20)
        } else if !blockedAppNames.isEmpty {
            blockedAppsCard
        } else {
            // Apple's FamilyControls API hides names for privacy; show the count.
            DashCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(accent.opacity(0.15))
                            .frame(width: 46, height: 46)
                        Image(systemName: isUnlocked ? "lock.open.fill" : "lock.shield.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(appsBlocked) item\(appsBlocked == 1 ? "" : "s") restricted")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ink)
                        Text(isUnlocked
                             ? "Currently unlocked — you hit today's goal."
                             : "Stay locked until you hit today's goal.")
                            .font(.system(size: 12))
                            .foregroundColor(.muted)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var shieldHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.10))
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 100, height: 100)
                Image(systemName: isUnlocked ? "lock.open.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(accent)
            }

            VStack(spacing: 4) {
                Text(isUnlocked ? "Apps Unlocked" : "Apps Blocked")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(.ink)
                Text(isUnlocked
                     ? "You earned your scroll time today."
                     : "Hit your goal to unlock restricted apps.")
                    .font(.system(size: 13))
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var progressCard: some View {
        DashCard(padding: .init(top: 16, leading: 18, bottom: 16, trailing: 18)) {
            VStack(spacing: 14) {
                HStack {
                    Label {
                        Text("Today's progress")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.muted)
                    } icon: {
                        Image(systemName: "flame.fill")
                            .foregroundColor(accent)
                    }
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(accent)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ringTrack)
                        Capsule()
                            .fill(LinearGradient(colors: [accent, accent.opacity(0.7)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 10)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(calories)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.ink)
                        Text("KCAL BURNED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.muted)
                            .tracking(0.6)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(isUnlocked ? "GOAL" : "\(remaining)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(isUnlocked ? .emeraldGreen : .ink)
                        Text(isUnlocked ? "MET" : "TO GO")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.muted)
                            .tracking(0.6)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var blockedAppsCard: some View {
        DashCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Restricted Apps")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.ink)
                    Spacer()
                    Text(isUnlocked ? "All open" : "All blocked")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isUnlocked ? .emeraldGreen : .rose)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill((isUnlocked ? Color.emeraldGreen : Color.rose).opacity(0.12))
                        )
                }
                ForEach(blockedAppNames.prefix(5), id: \.self) { name in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.ringTrack)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(name.prefix(1)))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.muted)
                            )
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.ink)
                        Spacer()
                        Image(systemName: isUnlocked ? "lock.open" : "lock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(isUnlocked ? .emeraldGreen : .rose)
                    }
                }
                if blockedAppNames.count > 5 {
                    Text("+\(blockedAppNames.count - 5) more")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.muted)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var quickStats: some View {
        HStack(spacing: 10) {
            quickStatTile(icon: "shield.fill", value: "\(appsBlocked)", label: "Apps")
            quickStatTile(icon: "flame.fill", value: "\(calories)", label: "Burned")
            quickStatTile(icon: "checkmark.circle.fill",
                          value: isUnlocked ? "Yes" : "No", label: "Unlocked")
        }
        .padding(.horizontal, 20)
    }

    private func quickStatTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accent)
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.muted)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 6, y: 1)
        )
    }
}

// MARK: - Rich Progress Section

/// Trends page — Energy hero, heart + steps statistics, and per-metric 7-day
/// charts for calories, steps, heart, sleep, energy, and strain. Tapping any
/// stat card or trend bar navigates into a 30-day `MetricDetailView`.
struct ProgressScreen: View {
    /// Drives navigation to the 30-day metric detail.
    @State private var detailMetric: MetricKind?
    /// Presents the interactive Swift Charts analytics page (D/W/M/6M).
    @State private var showAnalytics = false
    // Energy / Apple rings
    let energyScore: Double
    let moveProgress: Double
    let exerciseProgress: Double
    let standProgress: Double
    let exerciseMinutes: Double
    let standHours: Double

    // Today's headline stats
    let caloriesToday: Double
    let stepsToday: Int
    let hrv: Double
    let rhr: Double
    let resp: Double
    let sleepHours: Double
    let sleepEfficiency: Double

    // Heart / steps statistics (7-day aggregates)
    let weekRHRAvg: Int
    let weekRHRMin: Int
    let weekRHRMax: Int
    let weekStepsAvg: Int
    let weekStepsBest: Int
    let weekStepsTotal: Int
    let weekCaloriesAvg: Int

    // Trend histories (oldest → today, length 7)
    let caloriesHistory: [DayScore]
    let stepsHistory: [DayScore]
    let heartHistory: [DayScore]
    let sleepHistory: [DayScore]
    let energyHistory: [DayScore]
    let strainHistory: [DayScore]

    private var ringColor: Color {
        energyScore > 66 ? .emeraldGreen : energyScore > 33 ? .amber : .rose
    }
    private var ringLabel: String {
        energyScore > 80 ? "Fully charged"
            : energyScore > 50 ? "Building up"
            : energyScore > 0  ? "Low — keep moving"
            : "No data yet"
    }

    /// Move goal used to compute per-day Energy in the detail screen. Defaults to
    /// 500 (Apple's default); SoloProgressTab passes the user's real value.
    var energyMoveGoalKcal: Double = 500

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Text("TRENDS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.muted)
                    .tracking(0.9)
                    .padding(.top, 56)

                heroRing
                ringsBreakdown

                analyticsEntryCard

                sectionHeader("Heart Statistics", showChevron: true)
                    .onTapGesture { detailMetric = .heart }
                heartStatsCard
                    .onTapGesture { detailMetric = .heart }
                AppBiometricStrip(hrv: hrv, rhr: rhr, resp: resp)
                    .padding(.horizontal, 20)

                sectionHeader("Steps Statistics", showChevron: true)
                    .onTapGesture { detailMetric = .steps }
                stepsStatsCard
                    .onTapGesture { detailMetric = .steps }

                sectionHeader("Trends")
                trendCard(title: "Calories", color: Color(hex: "#FF6321"),
                          history: caloriesHistory, unit: " kcal", precision: 0)
                    .onTapGesture { detailMetric = .calories }
                trendCard(title: "Steps", color: Color(hex: "#34C99A"),
                          history: stepsHistory, unit: "", precision: 0, compact: true)
                    .onTapGesture { detailMetric = .steps }
                trendCard(title: "Heart", color: Color(hex: "#FF5A87"),
                          history: heartHistory, unit: " bpm", precision: 0)
                    .onTapGesture { detailMetric = .heart }
                trendCard(title: "Sleep", color: Color(hex: "#A897FF"),
                          history: sleepHistory, unit: "%", precision: 0)
                    .onTapGesture { detailMetric = .sleep }
                trendCard(title: "Energy", color: .electricOrange,
                          history: energyHistory, unit: "%", precision: 0)
                    .onTapGesture { detailMetric = .energy(moveGoalKcal: energyMoveGoalKcal) }
                trendCard(title: "Strain", color: .amber,
                          history: strainHistory, unit: "", precision: 1)
                    .onTapGesture { detailMetric = .strain }

                Spacer(minLength: 12)
            }
            .padding(.bottom, 24)
        }
        .sheet(item: $detailMetric) { metric in
            NavigationStack {
                MetricDetailView(metric: metric)
            }
        }
        .sheet(isPresented: $showAnalytics) {
            NavigationStack {
                ProgressAnalyticsView(moveGoalKcal: energyMoveGoalKcal)
            }
        }
    }

    // MARK: - Analytics entry card

    /// Prominent entry into the interactive Swift Charts analytics page.
    private var analyticsEntryCard: some View {
        Button { showAnalytics = true } label: {
            DashCard(padding: .init(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(colors: [.electricOrange, Color(hex: "#FF8C42")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 46, height: 46)
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Deep Analytics")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ink)
                        Text("Compare days, weeks & months — scrub charts, see your baselines & trends")
                            .font(.system(size: 11.5))
                            .foregroundColor(.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.electricOrange)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Section header
    private func sectionHeader(_ text: String, showChevron: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.muted)
                .tracking(0.9)
            Spacer()
            if showChevron {
                Text("View 30 days")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.electricOrange)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.electricOrange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Energy hero
    private var heroRing: some View {
        VStack(spacing: 10) {
            RecoveryRingView(
                fraction: energyScore / 100,
                value: "\(Int(energyScore))",
                unit: "%",
                label: "ENERGY",
                color: ringColor,
                ringSize: 180
            )
            Text(ringLabel)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ringColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(ringColor.opacity(0.12)))
        }
    }

    private var ringsBreakdown: some View {
        HStack(spacing: 10) {
            ringChip(label: "Move",     value: "\(Int(moveProgress * 100))%",
                     fraction: moveProgress, color: Color(hex: "#FF375F"))
            ringChip(label: "Exercise", value: "\(Int(exerciseMinutes)) min",
                     fraction: exerciseProgress, color: Color(hex: "#92E82A"))
            ringChip(label: "Stand",    value: "\(Int(standHours)) hr",
                     fraction: standProgress, color: Color(hex: "#0AC4D1"))
        }
        .padding(.horizontal, 20)
    }

    private func ringChip(label: String, value: String, fraction: Double, color: Color) -> some View {
        DashCard(padding: .init(top: 12, leading: 12, bottom: 12, trailing: 12)) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(color.opacity(0.18), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.001, min(fraction, 1)))
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 46, height: 46)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.ink)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.muted)
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Heart statistics card
    private var heartStatsCard: some View {
        DashCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            HStack(spacing: 0) {
                heartStatColumn(value: "\(Int(rhr))", unit: "bpm",   label: "Now",
                                tint: Color(hex: "#FF5A87"))
                Divider().frame(height: 32)
                heartStatColumn(value: "\(weekRHRAvg)", unit: "bpm", label: "Week avg",
                                tint: Color(hex: "#FF5A87"))
                Divider().frame(height: 32)
                heartStatColumn(value: weekRHRMin > 0 ? "\(weekRHRMin)" : "—",
                                unit: "min", label: "Lowest",
                                tint: .emeraldGreen)
                Divider().frame(height: 32)
                heartStatColumn(value: weekRHRMax > 0 ? "\(weekRHRMax)" : "—",
                                unit: "max", label: "Highest",
                                tint: .amber)
            }
        }
        .padding(.horizontal, 20)
    }

    private func heartStatColumn(value: String, unit: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.ink)
                Text(unit)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.muted)
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
                .tracking(0.4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Steps statistics card
    private var stepsStatsCard: some View {
        DashCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    stepsStatColumn(value: stepsToday >= 1000
                                    ? String(format: "%.1fk", Double(stepsToday) / 1000)
                                    : "\(stepsToday)",
                                    label: "Today")
                    Divider().frame(height: 32)
                    stepsStatColumn(value: weekStepsAvg >= 1000
                                    ? String(format: "%.1fk", Double(weekStepsAvg) / 1000)
                                    : "\(weekStepsAvg)",
                                    label: "Week avg")
                    Divider().frame(height: 32)
                    stepsStatColumn(value: weekStepsBest >= 1000
                                    ? String(format: "%.1fk", Double(weekStepsBest) / 1000)
                                    : "\(weekStepsBest)",
                                    label: "Best day")
                }
                Divider()
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill").font(.system(size: 11)).foregroundColor(.electricOrange)
                        Text("Calories today").font(.system(size: 12)).foregroundColor(.muted)
                    }
                    Spacer()
                    Text("\(Int(caloriesToday)) kcal · avg \(weekCaloriesAvg)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.ink)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func stepsStatColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.ink)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.muted)
                .tracking(0.4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trend bar chart
    private func trendCard(title: String, color: Color, history: [DayScore],
                           unit: String, precision: Int = 0,
                           compact: Bool = false) -> some View {
        let maxV = max(history.map { $0.value }.max() ?? 1, 1)
        let last = history.last?.value ?? 0
        let lastText: String = {
            if compact && last >= 1000 {
                return String(format: "%.1fk", last / 1000)
            }
            return precision == 0 ? "\(Int(last))" : String(format: "%.\(precision)f", last)
        }()

        return DashCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.ink)
                    Spacer()
                    Text("\(lastText)\(unit)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(color)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(history) { item in
                        let h = max(8, CGFloat(item.value / maxV) * 56)
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color.opacity(0.85))
                                .frame(height: h)
                            Text(String(item.day.prefix(1)))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 80)
            }
        }
        .padding(.horizontal, 20)
    }
}
