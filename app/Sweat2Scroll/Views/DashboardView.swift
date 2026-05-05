// Views/DashboardView.swift
// Direct 1:1 port of sscrollBestUI-main React app.
// Layout, component hierarchy, and visual design match App.tsx exactly.

import SwiftUI
import UIKit

// MARK: - Dashboard panes (PRD v2 bottom bar + hamburger navigate)
enum DashboardPane: Hashable {
    case solo
    case recovery
    case strain
    case sleep
    case social
    case partner
    case guardian

    static let menuNavigation: [DashboardPane] = [.solo, .recovery, .strain, .sleep, .social]
    static let bottomBar: [DashboardPane] = [.solo, .partner, .guardian, .social]

    var menuLabel: String {
        switch self {
        case .solo: return "HOME"
        case .recovery: return "RECOVERY"
        case .strain: return "STRAIN"
        case .sleep: return "SLEEP"
        case .social: return "SOCIAL"
        default: return ""
        }
    }

    var menuIcon: String {
        switch self {
        case .solo: return "flame.fill"
        case .recovery: return "heart.fill"
        case .strain: return "waveform.path.ecg"
        case .sleep: return "moon.fill"
        case .social: return "person.3.fill"
        default: return "circle"
        }
    }

    var bottomLabel: String {
        switch self {
        case .solo: return "SOLO"
        case .partner: return "PARTNER"
        case .guardian: return "GUARDIAN"
        case .social: return "SOCIAL"
        default: return ""
        }
    }

    var bottomIcon: String {
        switch self {
        case .solo: return "person.fill"
        case .partner: return "person.2.fill"
        case .guardian: return "figure.and.child.holdinghands"
        case .social: return "globe"
        default: return "circle"
        }
    }
}

// MARK: - Root Dashboard
struct DashboardView: View {
    @EnvironmentObject private var activityVM: ActivityViewModel
    @EnvironmentObject private var partnerVM: PartnerViewModel
    @EnvironmentObject private var screenTime: ScreenTimeService
    @EnvironmentObject private var onboardingVM: OnboardingViewModel

    @State private var activePane: DashboardPane = .solo
    @State private var showSettings = false
    @State private var showSelfReg = false
    @State private var showMenu = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.paper.ignoresSafeArea()

            // Background decoration blobs (matches React decorative divs)
            Circle()
                .fill(Color.electricOrange.opacity(0.05))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: 140, y: -200)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            Circle()
                .fill(Color.deepTeal.opacity(0.05))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: -160, y: 80)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 0) {
                    // MARK: Header
                    S2SHeader(showMenu: $showMenu)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    #if targetEnvironment(simulator)
                    SimulatorFamilyControlsBanner()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    #endif

                    if screenTime.authorizationStatus != .approved {
                        ScreenTimeAccessBanner(status: screenTime.authorizationStatus)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }

                    // MARK: Active Tab Content
                    Group {
                        switch activePane {
                        case .solo:
                            S2SHomeView(showSelfReg: $showSelfReg)
                        case .recovery:
                            S2SRecoveryView()
                        case .strain:
                            S2SStrainView()
                        case .sleep:
                            S2SSleepView()
                        case .social:
                            S2SSocialView()
                        case .partner:
                            PartnerTabRoot()
                        case .guardian:
                            GuardianView()
                        }
                    }
                    .padding(.horizontal, 24)
                    .animation(.easeInOut(duration: 0.25), value: activePane)

                    // Bottom padding so content clears the floating nav
                    Spacer(minLength: 120)
                }
            }

            // MARK: Floating Bottom Nav
            S2SBottomNav(activePane: $activePane)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

            // MARK: Side Menu Overlay
            if showMenu {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showMenu = false } }
                    .transition(.opacity)
            }
        }
        // Side drawer sits outside the bottom-aligned ZStack so it fills full height
        .overlay(alignment: .leading) {
            if showMenu {
                SideMenuView(
                    activePane: $activePane,
                    showSettings: $showSettings,
                    showMenu: $showMenu
                )
                .transition(.move(edge: .leading))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showMenu)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showSelfReg) {
            SelfRegulationSheet(activityVM: activityVM)
        }
        .task {
            await partnerVM.refreshPartnerData()
        }
    }
}

// MARK: - Header
struct S2SHeader: View {
    @Binding var showMenu: Bool

    var body: some View {
        HStack {
            // Hamburger button
            Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showMenu = true } }) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                        .frame(width: 40, height: 40)
                    VStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.ink)
                                .frame(width: 18, height: 2)
                        }
                    }
                }
            }

            Spacer()

            // Wordmark
            HStack(spacing: 8) {
                Sweat2ScrollLogo(size: 36)
                Text("SWEAT2SCROLL")
                    .font(.display(18))
                    .foregroundColor(.ink)
                    .tracking(-0.5)
            }
        }
    }
}

// MARK: - Side Menu
struct SideMenuView: View {
    @ObservedObject private var auth = AuthManager.shared
    @EnvironmentObject private var activityVM: ActivityViewModel
    @EnvironmentObject private var onboardingVM: OnboardingViewModel
    @EnvironmentObject private var partnerVM: PartnerViewModel

    @Binding var activePane: DashboardPane
    @Binding var showSettings: Bool
    @Binding var showMenu: Bool

    @State private var isEditingName = false
    @State private var editedName: String = ""
    @State private var showLogoutConfirm = false
    @State private var showPairFromMenu = false
    @State private var showSecurityDeniedAlert = false

    private var displayName: String {
        let stored = UserDefaults.standard.string(forKey: "display_name") ?? ""
        if !stored.isEmpty { return stored }
        return onboardingVM.userProfile.displayName.isEmpty ? "User" : onboardingVM.userProfile.displayName
    }

    private var nameInitials: String {
        let words = displayName.split(separator: " ").prefix(2)
        return words.map { String($0.prefix(1)).uppercased() }.joined()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Panel background
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.paper)
                .ignoresSafeArea()
                .shadow(color: .black.opacity(0.12), radius: 24, x: 6, y: 0)

            VStack(alignment: .leading, spacing: 0) {

                // MARK: Profile Section
                profileSection
                    .padding(.top, 64)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                Divider().padding(.horizontal, 16)

                // MARK: Navigation
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        menuSectionLabel("NAVIGATE")
                            .padding(.top, 20)

                        ForEach(DashboardPane.menuNavigation, id: \.self) { tab in
                            menuNavRow(tab)
                        }

                        Divider().padding(.vertical, 10).padding(.horizontal, 8)

                        menuSectionLabel("YOUR ROLE")
                        ForEach(AppMode.allCases, id: \.self) { mode in
                            menuRoleRow(mode)
                        }

                        Divider().padding(.vertical, 10).padding(.horizontal, 8)

                        menuSectionLabel("PAIRING")
                        if case .solo = auth.authState {
                            menuActionRow(
                                icon: "person.badge.key.fill",
                                label: "Add partner",
                                color: .deepTeal
                            ) {
                                Task { @MainActor in
                                    let ok = await SecurityGate.authenticate(reason: "Confirm to add a partner or guardian.")
                                    guard ok else {
                                        showSecurityDeniedAlert = true
                                        return
                                    }
                                    try? await auth.switchToMonitoredAndShowPairCodeEntry()
                                    showMenu = false
                                }
                            }
                        } else if case .user(let paired) = auth.authState, !paired {
                            menuActionRow(
                                icon: "key.horizontal.fill",
                                label: "Enter partner code",
                                color: .electricOrange
                            ) {
                                Task { @MainActor in
                                    let ok = await SecurityGate.authenticate(reason: "Confirm to enter a pairing code.")
                                    guard ok else {
                                        showSecurityDeniedAlert = true
                                        return
                                    }
                                    showPairFromMenu = true
                                    showMenu = false
                                }
                            }
                        } else if case .user(let paired) = auth.authState, paired {
                            Text("Paired with your partner.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }

                        Divider().padding(.vertical, 10).padding(.horizontal, 8)

                        menuSectionLabel("ACCOUNT")

                        // Settings row
                        menuActionRow(
                            icon: "gearshape.fill",
                            label: "Settings",
                            color: .muted
                        ) {
                            showMenu = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showSettings = true
                            }
                        }

                        Divider().padding(.vertical, 10).padding(.horizontal, 8)

                        // Logout row
                        menuActionRow(
                            icon: "arrow.right.square.fill",
                            label: "Log Out",
                            color: Color(hex: "#FF6B6B")
                        ) {
                            showLogoutConfirm = true
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(width: 300)
        .ignoresSafeArea()
        .sheet(isPresented: $showPairFromMenu) {
            NavigationStack { PairCodeEntryView() }
        }
        .confirmationDialog("Log out of Sweat2Scroll?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                logout()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Authentication required", isPresented: $showSecurityDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use Face ID or your device passcode to change pairing.")
        }
    }

    // MARK: Profile Section
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Color.electricOrange, Color(hex: "#FF9A62")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.electricOrange.opacity(0.3), radius: 10, y: 4)
                Text(nameInitials)
                    .font(.display(22))
                    .foregroundColor(.white)
            }

            // Name (editable)
            if isEditingName {
                HStack(spacing: 8) {
                    TextField("Display name", text: $editedName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.ink.opacity(0.05))
                        .cornerRadius(10)
                        .submitLabel(.done)
                        .onSubmit { saveName() }

                    Button(action: saveName) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.electricOrange)
                    }
                    Button(action: { isEditingName = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.muted)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.ink)
                    Button(action: {
                        editedName = displayName
                        isEditingName = true
                    }) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.muted)
                    }
                }
            }

            // Partner status pill
            HStack(spacing: 6) {
                Circle()
                    .fill(partnerVM.isPartnerPaired ? Color.emeraldGreen : Color.muted)
                    .frame(width: 7, height: 7)
                Text(partnerVM.isPartnerPaired
                     ? "Paired with \(partnerVM.partnerDisplayName)"
                     : "No partner connected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.muted)
            }
        }
    }

    private func roleCopy(_ mode: AppMode) -> (String, String, String) {
        switch mode {
        case .solo:
            ("person.fill", "Solo", "Train and scroll on your own")
        case .user:
            ("figure.walk", "Partner", "Earn scroll with someone holding the code")
        case .monitor:
            ("figure.and.child.holdinghands", "Guardian", "Set rules and share a 6-digit pair code")
        }
    }

    private func isRoleActive(_ mode: AppMode) -> Bool {
        switch (auth.authState, mode) {
        case (.solo, .solo), (.user, .user), (.monitor, .monitor):
            return true
        default:
            return false
        }
    }

    // MARK: Role row (Solo / Monitored / Monitor)
    private func menuRoleRow(_ mode: AppMode) -> some View {
        let active = isRoleActive(mode)
        let (icon, title, subtitle) = roleCopy(mode)
        return Button(action: {
            Task { @MainActor in
                try? await auth.switchAppMode(mode)
                showMenu = false
            }
        }) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(active ? Color.electricOrange : Color.ink.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: active ? .bold : .medium))
                        .foregroundColor(active ? .white : .muted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: active ? .bold : .medium))
                        .foregroundColor(.ink)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.electricOrange)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                active
                    ? RoundedRectangle(cornerRadius: 14).fill(Color.electricOrange.opacity(0.08))
                    : RoundedRectangle(cornerRadius: 14).fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Nav Row
    private func menuNavRow(_ tab: DashboardPane) -> some View {
        let isActive = activePane == tab
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                activePane = tab
                showMenu = false
            }
        }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? Color.electricOrange : Color.ink.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: tab.menuIcon)
                        .font(.system(size: 15, weight: isActive ? .bold : .medium))
                        .foregroundColor(isActive ? .white : .muted)
                }
                Text(tab.menuLabel)
                    .font(.system(size: 15, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? .ink : .muted)
                Spacer()
                if isActive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.electricOrange)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 14).fill(Color.electricOrange.opacity(0.08))
                    : RoundedRectangle(cornerRadius: 14).fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Action Row
    private func menuActionRow(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(label == "Log Out" ? color : .ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.muted.opacity(0.5))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    private func menuSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2)
            .foregroundColor(.muted)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    // MARK: Helpers
    private func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: "display_name")
            onboardingVM.userProfile.displayName = trimmed
        }
        isEditingName = false
    }

    private func logout() {
        AuthManager.shared.signOut()
        UserDefaults.standard.removeObject(forKey: "is_authenticated")
        UserDefaults.standard.removeObject(forKey: "display_name")
        showMenu = false
    }
}

// MARK: - Bottom Nav
struct S2SBottomNav: View {
    @Binding var activePane: DashboardPane

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DashboardPane.bottomBar, id: \.self) { tab in
                Button(action: { activePane = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.bottomIcon)
                            .font(.system(size: 20, weight: activePane == tab ? .bold : .regular))
                            .foregroundColor(activePane == tab ? Color(red: 0.91, green: 0.40, blue: 0.10) : .muted)
                        Text(tab.bottomLabel)
                            .font(.system(size: 9, weight: .bold, design: .default))
                            .tracking(-0.3)
                            .foregroundColor(activePane == tab ? Color(red: 0.91, green: 0.40, blue: 0.10) : .muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(
            Capsule()
                .fill(.thinMaterial)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 8)
        )
    }
}

// MARK: - Screen Time / Simulator banners
private struct ScreenTimeAccessBanner: View {
    let status: ScreenTimeService.AuthorizationStatus

    private var message: String {
        switch status {
        case .approved:
            return ""
        case .notDetermined:
            return "Approve Screen Time access when prompted so Sweat2Scroll can shield selected apps after your goal."
        case .denied:
            return "Screen Time access is off. Open Settings → Screen Time and allow Sweat2Scroll to lock apps until you earn access."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundColor(.electricOrange)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.electricOrange.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.electricOrange.opacity(0.35), lineWidth: 1))
        )
    }
}

#if targetEnvironment(simulator)
private struct SimulatorFamilyControlsBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone.slash")
                .font(.title3)
                .foregroundColor(.deepTeal)
            Text("Simulator cannot run Screen Time shields. Build to a physical iPhone to test app blocking.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.deepTeal.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.deepTeal.opacity(0.28), lineWidth: 1))
        )
    }
}
#endif

// MARK: - Gauge (matches React <Gauge> component exactly)
struct S2SGauge: View {
    let value: Int           // 0–100
    let label: String
    let color: Color
    var size: CGFloat = 160
    var strokeWidth: CGFloat = 12

    @State private var animated = false

    private var fraction: Double { Double(value) / 100.0 }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.ringTrack, lineWidth: strokeWidth)
                .frame(width: size, height: size)

            // Colored arc
            Circle()
                .trim(from: 0, to: animated ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: animated)

            // Center label
            VStack(spacing: 3) {
                Text("\(value)")
                    .font(.display(size * 0.28))
                    .foregroundColor(.ink)
                Text(label.uppercased())
                    .font(.system(size: size * 0.07, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.muted)
            }
        }
        .onAppear { animated = true }
    }
}

// MARK: - Progress Ring (matches React <ProgressRing> component)
struct S2SProgressRing: View {
    let progress: Double     // 0–100
    let value: String
    let label: String
    var size: CGFloat = 180
    var strokeWidth: CGFloat = 12

    @State private var animated = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ringTrack, lineWidth: strokeWidth)
                .frame(width: size - strokeWidth, height: size - strokeWidth)

            Circle()
                .trim(from: 0, to: animated ? min(progress / 100, 1.0) : 0)
                .stroke(Color.electricOrange, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size - strokeWidth, height: size - strokeWidth)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: animated)

            VStack(spacing: 4) {
                Text(value)
                    .font(.display(52))
                    .foregroundColor(.ink)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.muted)
            }
        }
        .frame(width: size, height: size)
        .onAppear { animated = true }
    }
}

// MARK: - Stat Card (matches React <StatCard> component)
struct S2SStatCard: View {
    let systemImage: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(color.opacity(0.10))
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            .padding(.bottom, 4)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.display(24))
                    .foregroundColor(.ink)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.muted)
                }
            }

            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        )
    }
}

// MARK: - Partner / Guardian tabs (PRD §4A placeholders — wire CloudKit peer stats next)
private struct PartnerTabRoot: View {
    @EnvironmentObject private var partnerVM: PartnerViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("PARTNER")
                .font(.capsLabel(12))
                .foregroundColor(.muted)
            if partnerVM.isPartnerPaired {
                Text("Paired with \(partnerVM.partnerDisplayName)")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("Partner progress and goals sync here when pairing is fully enabled.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.muted)
                Text("No partner connected")
                    .font(.title3.bold())
                Text("Use the menu → Pairing → Add partner to link with someone.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

// MARK: - Home View (sscrollBestUI layout + live Activity / Partner / Wellness data)
struct S2SHomeView: View {
    @EnvironmentObject private var activityVM: ActivityViewModel
    @EnvironmentObject private var partnerVM: PartnerViewModel
    @EnvironmentObject private var wellnessVM: WellnessViewModel

    @Binding var showSelfReg: Bool

    private var progressPercent: Double { activityVM.activityGoal.progressFraction * 100 }

    private var statusBannerTitle: String {
        if activityVM.isUnlocked { return "Goal Earned" }
        if activityVM.isShieldActive { return "Shield Active" }
        return "Working Toward Goal"
    }

    private var statusBannerSubtitle: String {
        if activityVM.isUnlocked { return "All apps are now unlocked" }
        let g = activityVM.activityGoal
        switch g.currency {
        case .activeCalories:
            return "Apps unlock at \(Int(g.agreedTarget)) kcal"
        case .steps:
            return "\(Int(g.remaining)) steps to unlock"
        }
    }

    private var statusBannerOrange: Bool {
        !(activityVM.isUnlocked)
    }

    private var ringCenterText: String {
        switch activityVM.activityGoal.currency {
        case .activeCalories:
            return "\(Int(activityVM.activityGoal.currentProgress.rounded()))"
        case .steps:
            return "\(activityVM.stepsToday)"
        }
    }

    private var ringUnitLabel: String {
        activityVM.activityGoal.currency == .activeCalories ? "kcal" : "steps"
    }

    private var remainingMain: Int {
        Int(activityVM.activityGoal.remaining.rounded())
    }

    private var remainingUnit: String {
        activityVM.activityGoal.currency == .activeCalories ? "kcal" : "steps"
    }

    var body: some View {
        VStack(spacing: 24) {

            // MARK: Status Banner
            HStack {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: statusBannerOrange ? "shield.fill" : "bolt.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusBannerTitle)
                            .font(.display(17))
                            .foregroundColor(.white)
                        Text(statusBannerSubtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.80))
                    }
                }
                Spacer()
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(statusBannerOrange ? Color.electricOrange : Color.deepTeal)
            )

            if activityVM.isGracePeriodActive {
                GracePeriodBannerView(remaining: activityVM.gracePeriodRemainingSeconds)
            }
            if activityVM.isSyncTimerActive {
                SyncTimerView(remaining: activityVM.syncTimerRemainingSeconds)
            }

            // MARK: Main Progress Card
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Color.ringTrack
                        Color.electricOrange
                            .frame(width: geo.size.width * min(progressPercent / 100, 1.0))
                            .animation(.easeOut(duration: 1.0), value: progressPercent)
                    }
                }
                .frame(height: 4)

                VStack(spacing: 32) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PROGRESS")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.muted)
                            Text("\(Int(progressPercent))%")
                                .font(.display(24))
                                .foregroundColor(.ink)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("REMAINING")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.muted)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(remainingMain)")
                                    .font(.display(24))
                                    .foregroundColor(.ink)
                                Text(remainingUnit)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.muted)
                            }
                        }
                    }

                    S2SProgressRing(
                        progress: progressPercent,
                        value: ringCenterText,
                        label: ringUnitLabel
                    )

                    HStack(spacing: 12) {
                        HomeMetricPill(
                            systemImage: "flame.fill",
                            iconColor: .electricOrange,
                            metricLabel: "GOAL",
                            metricValue: activityVM.activityGoal.currency == .activeCalories
                                ? "\(Int(activityVM.activityGoal.agreedTarget)) kcal"
                                : "\(Int(activityVM.activityGoal.agreedTarget)) steps"
                        )
                        HomeMetricPill(
                            systemImage: "figure.walk",
                            iconColor: .deepTeal,
                            metricLabel: "STEPS",
                            metricValue: s2sFormatInteger(activityVM.stepsToday)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
            .background(
                RoundedRectangle(cornerRadius: 40)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 40).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 40))

            ShieldToggleView(
                isActive: activityVM.isShieldActive,
                isUnlocked: activityVM.isUnlocked
            ) { enabled in
                activityVM.toggleShield(enabled: enabled)
            }

            if activityVM.isShieldActive && !activityVM.isUnlocked {
                Button(action: { showSelfReg = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.slash")
                        Text("I need a break")
                    }
                    .font(.caption)
                    .foregroundColor(.muted)
                }
            }

            // MARK: 2x2 Stat Grid (wellness VM — sample / estimated until full HealthKit sync)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                S2SStatCard(systemImage: "heart.fill", label: "Recovery",
                            value: "\(Int(wellnessVM.recoveryScore))", unit: "%", color: .emeraldGreen)
                S2SStatCard(systemImage: "waveform.path.ecg", label: "Strain",
                            value: String(format: "%.1f", wellnessVM.strainScore), unit: "", color: .electricOrange)
                S2SStatCard(systemImage: "moon.fill", label: "Sleep",
                            value: "\(Int(wellnessVM.sleepScore))", unit: "%", color: .deepTeal)
                S2SStatCard(systemImage: "timer", label: "HRV",
                            value: "\(Int(wellnessVM.hrv))", unit: "ms", color: .s2sPurple)
            }

            Text("Recovery, strain, sleep, and HRV shown here are sample estimates until fully driven by HealthKit.")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // MARK: Partner Card
            s2sPartnerSummaryCard

            // MARK: Editorial Quote
            VStack(spacing: 8) {
                Text("Earn your\nscroll time.")
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundColor(.ink)
                    .lineSpacing(2)
                Text("Apps stay locked until your body earns the access.\nEvery. Single. Day.")
                    .font(.system(size: 14, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.muted)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private var s2sPartnerSummaryCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.deepTeal)
                    .frame(width: 48, height: 48)
                Text(partnerInitial)
                    .font(.display(20))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(partnerVM.isPartnerPaired ? partnerVM.partnerDisplayName : "Partner")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.ink)
                Text(partnerVM.isPartnerPaired ? partnerVM.partnerProgressSummaryLine : "Pair in Settings to share progress.")
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
            }
            Spacer()
            Circle()
                .fill(partnerStatusColor)
                .frame(width: 10, height: 10)
                .shadow(color: partnerStatusColor.opacity(0.5), radius: 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        )
    }

    private var partnerInitial: String {
        guard partnerVM.isPartnerPaired else { return "?" }
        return String(partnerVM.partnerDisplayName.prefix(1)).uppercased()
    }

    private var partnerStatusColor: Color {
        guard partnerVM.isPartnerPaired else { return Color.muted }
        return partnerVM.partnerProgressFraction >= 1.0 ? Color.emeraldGreen : Color.electricOrange
    }
}

private func s2sFormatInteger(_ value: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: value)) ?? "\(value)"
}

// Small sub-component for goal/steps pills in HomeView
private struct HomeMetricPill: View {
    let systemImage: String
    let iconColor: Color
    let metricLabel: String
    let metricValue: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconColor.opacity(0.10))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(iconColor)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(metricLabel)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.muted)
                Text(metricValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.20))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
        )
    }
}

// MARK: - Recovery View (matches React RecoveryView)
struct S2SRecoveryView: View {
    @EnvironmentObject private var wellnessVM: WellnessViewModel

    var body: some View {
        VStack(spacing: 24) {

            Text("Sample wellness data — connect HealthKit for live recovery.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)

            // Main Gauge Card
            VStack(spacing: 0) {
                Text(wellnessVM.recoveryLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundColor(.muted)
                    .padding(.bottom, 32)

                S2SGauge(value: min(Int(wellnessVM.recoveryScore), 100), label: "Recovery", color: .emeraldGreen)

                // 3-col metrics row
                HStack(spacing: 0) {
                    RecoveryMetricCol(label: "HRV",       value: "\(Int(wellnessVM.hrv))", unit: "ms", trend: "up")
                    Divider().frame(height: 40)
                    RecoveryMetricCol(label: "RHR",       value: "\(Int(wellnessVM.rhr))", unit: "bpm", trend: "down")
                    Divider().frame(height: 40)
                    RecoveryMetricCol(label: "RESP",      value: String(format: "%.1f", wellnessVM.respiratoryRate), unit: "br", trend: "dot")
                }
                .padding(.top, 40)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 40)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 40).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )

            // Recovery Insights card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.muted)
                    Text("Recovery Insights")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.ink)
                }
                Text("\"Recovery scores here use sample pacing from HealthKit-style metrics. Full personalization ships with deeper sensor sync.\"")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(.muted)
                    .lineSpacing(4)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )

            // 7-Day list
            VStack(alignment: .leading, spacing: 12) {
                Text("LAST 7 DAYS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundColor(.muted)
                    .padding(.horizontal, 8)

                ForEach(wellnessVM.recoveryHistory) { day in
                    RecoveryDayRow(dayLabel: day.day, percent: min(Int(day.value), 100))
                }
            }
        }
    }
}

private struct RecoveryMetricCol: View {
    let label: String
    let value: String
    let unit: String
    let trend: String  // "up", "down", "dot"

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.muted)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.display(20)).foregroundColor(.ink)
                Text(unit).font(.system(size: 10)).foregroundColor(.muted)
            }
            if trend == "up" || trend == "down" {
                Image(systemName: trend == "up" ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11)).foregroundColor(.emeraldGreen)
            } else {
                Circle().fill(Color.emeraldGreen).frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RecoveryDayRow: View {
    let dayLabel: String
    let percent: Int

    private var barColor: Color {
        percent > 66 ? .emeraldGreen : percent > 33 ? .amber : .rose
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(dayLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.muted)
                .frame(width: 52, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Color.ringTrack.clipShape(Capsule())
                    barColor
                        .frame(width: geo.size.width * CGFloat(percent) / 100)
                        .clipShape(Capsule())
                }
            }
            .frame(height: 8)

            Text("\(percent)%")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.ink)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        )
    }
}

// MARK: - Strain View (matches React StrainView)
struct S2SStrainView: View {
    @EnvironmentObject private var wellnessVM: WellnessViewModel

    private var strainGaugePercent: Int {
        min(Int((wellnessVM.strainScore / 21.0) * 100), 100)
    }

    private var workoutsAvgHR: Int {
        guard !wellnessVM.workouts.isEmpty else { return 0 }
        let sum = wellnessVM.workouts.map(\.avgHR).reduce(0, +)
        return Int((sum / Double(wellnessVM.workouts.count)).rounded())
    }

    private var workoutsMaxHR: Int {
        let peaks = wellnessVM.workouts.map { session in
            session.heartRates.map(\.bpm).max() ?? session.avgHR
        }
        return Int((peaks.max() ?? 0).rounded())
    }

    var body: some View {
        VStack(spacing: 24) {

            Text("Sample strain curve — workouts below mirror WellnessViewModel until live sync.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)

            // Main Gauge Card
            VStack(spacing: 0) {
                Text("DAILY STRAIN")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundColor(.muted)
                    .padding(.bottom, 32)

                S2SGauge(
                    value: strainGaugePercent,
                    label: "Strain (\(String(format: "%.1f", wellnessVM.strainScore)))",
                    color: .electricOrange
                )

                // HR Zones bar
                VStack(spacing: 12) {
                    HStack {
                        Text("HEART RATE ZONES")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.muted)
                        Spacer()
                        Text("1h 12m total")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.muted)
                    }

                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.ringTrack)
                                .frame(width: geo.size.width * 0.20)
                            Rectangle()
                                .fill(Color.yellow)
                                .frame(width: geo.size.width * 0.30)
                            Rectangle()
                                .fill(Color.electricOrange)
                                .frame(width: geo.size.width * 0.40)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.rose)
                                .frame(width: geo.size.width * 0.10)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(height: 48)

                    HStack {
                        ForEach(["Zone 2", "Zone 3", "Zone 4", "Zone 5"], id: \.self) { zone in
                            Text(zone)
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.top, 40)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 40)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 40).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )

            // Avg HR / Max HR cards
            HStack(spacing: 16) {
                StrainMetricCard(label: "AVG HR", value: "\(workoutsAvgHR)", unit: "bpm")
                StrainMetricCard(label: "MAX HR", value: "\(workoutsMaxHR)", unit: "bpm")
            }

            // Activity Breakdown card
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity Breakdown")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.ink)

                ForEach(wellnessVM.workouts.prefix(2)) { session in
                    ActivityRow(
                        systemImage: session.icon,
                        iconColor: .electricOrange,
                        title: session.name,
                        subtitle: "\(session.duration) min • \(Int(session.calories)) kcal",
                        strainValue: String(format: "%.1f", session.strain)
                    )
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )
        }
    }
}

private struct StrainMetricCard: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.display(24)).foregroundColor(.ink)
                Text(unit).font(.system(size: 12)).foregroundColor(.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        )
    }
}

private struct ActivityRow: View {
    let systemImage: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let strainValue: String

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor == .ink ? Color.ringTrack : iconColor.opacity(0.10))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(iconColor)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.ink)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.muted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(strainValue).font(.system(size: 14, weight: .bold)).foregroundColor(.ink)
                Text("STRAIN")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.muted)
            }
        }
    }
}

// MARK: - Sleep View (matches React SleepView)
struct S2SSleepView: View {
    @EnvironmentObject private var wellnessVM: WellnessViewModel

    private var sleepTotalMinutes: Double {
        wellnessVM.sleepDeep + wellnessVM.sleepREM + wellnessVM.sleepLight + max(wellnessVM.sleepAwake, 1)
    }

    private func sleepStagePercent(_ minutes: Double) -> Int {
        guard sleepTotalMinutes > 0 else { return 0 }
        return min(Int((minutes / sleepTotalMinutes) * 100), 100)
    }

    private func formatSleepMinutes(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return "\(h)h \(m)m"
    }

    private var sleepStages: [(label: String, minutes: Double, color: Color)] {
        [
            ("REM",   wellnessVM.sleepREM,   Color.s2sPurple),
            ("Deep",  wellnessVM.sleepDeep,  Color.deepTeal),
            ("Light", wellnessVM.sleepLight, Color(red: 0.63, green: 0.63, blue: 0.63))
        ]
    }

    var body: some View {
        VStack(spacing: 24) {

            Text("Sample sleep architecture — totals come from WellnessViewModel staging data.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)

            // Main Gauge Card
            VStack(spacing: 0) {
                Text("SLEEP PERFORMANCE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundColor(.muted)
                    .padding(.bottom, 32)

                S2SGauge(value: min(Int(wellnessVM.sleepScore), 100), label: "Efficiency", color: .ink)

                // 2-col stats
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("TIME ASLEEP")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(.muted)
                        Text(wellnessVM.sleepHoursText).font(.display(20)).foregroundColor(.ink)
                    }
                    .frame(maxWidth: .infinity)
                    Divider().frame(height: 40)
                    VStack(spacing: 4) {
                        Text("CONSISTENCY")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(.muted)
                        Text("\(Int(wellnessVM.sleepConsistency * 100))%")
                            .font(.display(20))
                            .foregroundColor(.ink)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 40)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 40)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 40).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )

            // Sleep Stages card
            VStack(alignment: .leading, spacing: 20) {
                Text("Sleep Stages")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.ink)

                ForEach(sleepStages, id: \.label) { stage in
                    VStack(spacing: 8) {
                        HStack {
                            Text(stage.label)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.muted)
                            Spacer()
                            Text(formatSleepMinutes(stage.minutes))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.ink)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Color.ringTrack.clipShape(Capsule())
                                stage.color
                                    .frame(width: geo.size.width * CGFloat(sleepStagePercent(stage.minutes)) / 100)
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )

            // Sleep Debt card
            HStack {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.deepTeal.opacity(0.10))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.deepTeal)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Debt")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.ink)
                        Text("You need 12m more tonight")
                            .font(.system(size: 12)).foregroundColor(.muted)
                    }
                }
                Spacer()
                Text("+12m")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.rose)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )
        }
    }
}

// MARK: - Social View (matches React SocialView)
struct S2SSocialView: View {
    @EnvironmentObject private var wellnessVM: WellnessViewModel
    @State private var showFriendSearch = false
    @State private var friendSearchQuery = ""

    struct SocialUser: Identifiable {
        let id = UUID()
        let name: String
        let score: Int
        let goal: Int
        let streak: Int
        let initial: String
        let isMe: Bool
    }

    private let rawUsers: [SocialUser] = [
        .init(name: "You",   score: 246, goal: 300, streak: 12, initial: "Y", isMe: true),
        .init(name: "Alex",  score: 284, goal: 300, streak: 8,  initial: "A", isMe: false),
        .init(name: "Sarah", score: 412, goal: 400, streak: 24, initial: "S", isMe: false),
        .init(name: "Mike",  score: 182, goal: 350, streak: 3,  initial: "M", isMe: false),
        .init(name: "Emma",  score: 310, goal: 300, streak: 15, initial: "E", isMe: false)
    ]

    private var sorted: [SocialUser] {
        rawUsers.sorted { Double($0.score) / Double($0.goal) > Double($1.score) / Double($1.goal) }
    }

    var body: some View {
        VStack(spacing: 24) {

            Text("Leaderboard uses placeholder friends; activity feed pulls from WellnessViewModel samples.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)

            // Header row
            HStack {
                Text("LEADERBOARD")
                    .font(.display(24))
                    .foregroundColor(.ink)
                Spacer()
                HStack(spacing: 10) {
                    SocialIconButton(systemImage: "square.and.arrow.up")
                    Button { showFriendSearch = true } label: {
                        SocialIconButton(systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.plain)
                }
            }

            // Leaderboard rows
            VStack(spacing: 16) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, user in
                    LeaderboardUserRow(user: user, rank: i)
                }
            }

            // Recent Activity card
            VStack(alignment: .leading, spacing: 16) {
                Text("Recent Activity")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.ink)

                if let feed = wellnessVM.activityFeed.first {
                    HStack(alignment: .top, spacing: 16) {
                        Circle()
                            .fill(Color.ringTrack)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(feed.partnerInitial)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.ink)
                            )
                        VStack(alignment: .leading, spacing: 6) {
                            (Text(feed.partnerName).fontWeight(.bold) + Text(" \(feed.action)"))
                                .font(.system(size: 14))
                                .foregroundColor(.ink)
                            Text("\"\(feed.value)\"")
                                .font(.system(size: 12))
                                .foregroundColor(.muted)
                                .lineSpacing(3)
                            HStack(spacing: 20) {
                                HStack(spacing: 4) {
                                    Image(systemName: "hands.clap").font(.system(size: 12))
                                    Text("\(feed.applauds)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                }
                                .foregroundColor(.muted)
                                Text(feed.timestamp, style: .relative)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.muted)
                            }
                            .padding(.top, 4)
                        }
                    }
                } else {
                    Text("No feed items yet.")
                        .font(.subheadline)
                        .foregroundColor(.muted)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )
        }
        .sheet(isPresented: $showFriendSearch) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Search by username", text: $friendSearchQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Send invite (stub)") {
                            showFriendSearch = false
                        }
                    }
                    Section("Invite link") {
                        Text("https://sweat2scroll.app/invite/demo")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        Button("Copy link") {
                            UIPasteboard.general.string = "https://sweat2scroll.app/invite/demo"
                        }
                    }
                }
                .navigationTitle("Add friend")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showFriendSearch = false }
                    }
                }
            }
        }
    }
}

private struct SocialIconButton: View {
    let systemImage: String
    var body: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                .frame(width: 40, height: 40)
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.ink)
        }
    }
}

private struct LeaderboardUserRow: View {
    let user: S2SSocialView.SocialUser
    let rank: Int

    var body: some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(user.isMe ? Color.electricOrange : Color.deepTeal)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(user.initial)
                            .font(.display(20))
                            .foregroundColor(.white)
                    )
                if rank == 0 {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white)
                        )
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .offset(x: 4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(user.isMe ? "\(user.name) (You)" : user.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.ink)
                Text("\(user.score) / \(user.goal) KCAL")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.muted)
            }
            .padding(.leading, 12)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.electricOrange)
                    Text("\(user.streak)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.ink)
                }
                Text("STREAK")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            user.isMe ? Color.electricOrange.opacity(0.30) : Color.white.opacity(0.6),
                            lineWidth: 1
                        )
                )
        )
        .overlay(
            // Subtle orange tint overlay for "you" row
            Group {
                if user.isMe {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.electricOrange.opacity(0.05))
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Color extension for purple (not in main DesignSystem)
extension Color {
    static let s2sPurple = Color(red: 0.60, green: 0.40, blue: 0.90)
}
