// Views/HomeView.swift
// Main dashboard. Shows:
//   - Progress ring (calories/steps toward daily goal)
//   - Single master shield toggle
//   - Grace period / sync timer status
//   - Partner progress card
//   - Navigation to Settings, Partner, Audit Log

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var activityVM: ActivityViewModel
    @EnvironmentObject var partnerVM: PartnerViewModel
    @State private var showBreakGlass = false
    @State private var showSettings   = false
    @State private var showAuditLog   = false
    @State private var showSelfRegDialog = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paper.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {

                        // MARK: Progress Ring
                        ProgressRingView(
                            progress: activityVM.activityGoal.progressFraction,
                            current: activityVM.activityGoal.currentProgress,
                            goal: activityVM.activityGoal.agreedTarget,
                            currency: activityVM.activityGoal.currency,
                            isUnlocked: activityVM.isUnlocked
                        )
                        .padding(.top, 20)

                        // MARK: Status Banner
                        StatusBannerView(activityVM: activityVM)

                        // MARK: Single Master Shield Toggle
                        ShieldToggleView(
                            isActive: activityVM.isShieldActive,
                            isUnlocked: activityVM.isUnlocked
                        ) { enabled in
                            activityVM.toggleShield(enabled: enabled)
                        }

                        // MARK: Grace Period / Sync Timer
                        if activityVM.isGracePeriodActive {
                            GracePeriodBannerView(remaining: activityVM.gracePeriodRemainingSeconds)
                        }

                        if activityVM.isSyncTimerActive {
                            SyncTimerView(remaining: activityVM.syncTimerRemainingSeconds)
                        }

                        // MARK: Partner Card
                        PartnerProgressCard(partnerVM: partnerVM)

                        // MARK: Action Buttons
                        HStack(spacing: 16) {
                            ActionButton(title: "Break-Glass", systemImage: "key.fill", color: .orange) {
                                showBreakGlass = true
                            }
                            ActionButton(title: "Audit Log", systemImage: "list.bullet.clipboard", color: .blue) {
                                showAuditLog = true
                            }
                        }
                        .padding(.horizontal)

                        // Self-regulation bypass — visible when shield is active and goal not met
                        if activityVM.isShieldActive && !activityVM.isUnlocked {
                            Button(action: { showSelfRegDialog = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "hand.raised.slash")
                                    Text("I need a break")
                                }
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.3))
                            }
                            .padding(.top, 4)
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Sweat2Scroll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showBreakGlass) {
                BreakGlassView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAuditLog) {
                AuditLogView()
            }
            .sheet(isPresented: $showSelfRegDialog) {
                SelfRegulationSheet(activityVM: activityVM)
            }
        }
        .preferredColorScheme(.light)
        .task {
            await partnerVM.refreshPartnerData()
        }
    }
}

// MARK: - Self-Regulation Bypass Sheet (Motivational Friction)
// Forces the user to type a justification before temporarily dropping the shield.
// The justification is logged to the audit trail and shown to them the next morning.
struct SelfRegulationSheet: View {
    @ObservedObject var activityVM: ActivityViewModel
    @Environment(\.dismiss) var dismiss
    @State private var justification: String = ""
    @State private var selectedDuration: Int = 15
    @State private var hasAcknowledged = false

    private let durations = [5, 15, 30]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundColor(.orange.opacity(0.7))
                    .padding(.top, 24)

                Text("Take a Moment")
                    .font(.title2.bold())

                Text("This isn't a punishment. It's a check-in with yourself. Why do you want to override right now?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Justification text field
                TextField("What's going on?", text: $justification, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                // Duration picker
                VStack(spacing: 8) {
                    Text("How long do you need?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        ForEach(durations, id: \.self) { mins in
                            Button(action: { selectedDuration = mins }) {
                                Text("\(mins) min")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(selectedDuration == mins ? Color.orange.opacity(0.2) : Color(.systemGray6))
                                    .foregroundColor(selectedDuration == mins ? .orange : .secondary)
                                    .cornerRadius(10)
                            }
                        }
                    }
                }

                // Acknowledgement — .checkbox is macOS-only; use a tap-to-toggle button on iOS.
                Button(action: { hasAcknowledged.toggle() }) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: hasAcknowledged ? "checkmark.square.fill" : "square")
                            .foregroundColor(hasAcknowledged ? .orange : .secondary)
                            .font(.title3)
                        Text("I understand this will be logged and visible to my partner.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Spacer()

                // Confirm button
                Button(action: {
                    activityVM.requestSelfBypass(
                        duration: selectedDuration,
                        justification: justification.isEmpty ? "No reason given" : justification
                    )
                    dismiss()
                }) {
                    Text("Override for \(selectedDuration) minutes")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(hasAcknowledged && !justification.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.orange : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .disabled(!hasAcknowledged || justification.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationTitle("Self-Regulation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Status Banner (sscrollBestUI style)
struct StatusBannerView: View {
    @ObservedObject var activityVM: ActivityViewModel

    var body: some View {
        ShieldStatusBanner(
            isUnlocked: activityVM.isUnlocked,
            kcalRemaining: Int(activityVM.activityGoal.remaining.rounded()),
            progressPercent: Int((activityVM.activityGoal.progressFraction * 100).rounded())
        )
    }
}

// MARK: - Grace Period Banner
struct GracePeriodBannerView: View {
    let remaining: Int
    var body: some View {
        HStack {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(.amber)
            Text("Grace period: \(remaining)s — sync pending")
                .font(.capsLabel(13))
                .foregroundColor(.amber)
        }
        .padding(12)
        .background(Color.amber.opacity(0.12))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.amber.opacity(0.25), lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - Sync Timer View
struct SyncTimerView: View {
    let remaining: Int
    var body: some View {
        HStack {
            ProgressView().tint(.deepTeal)
            Text("Syncing Apple Watch data... \(remaining)s")
                .font(.capsLabel(13))
                .foregroundColor(.deepTeal)
        }
        .padding(12)
        .background(Color.deepTeal.opacity(0.08))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.deepTeal.opacity(0.2), lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - Partner Progress Card
struct PartnerProgressCard: View {
    @ObservedObject var partnerVM: PartnerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if partnerVM.isPartnerPaired {
                HStack {
                    ZStack {
                        Circle().fill(Color.deepTeal).frame(width: 36, height: 36)
                        Text(String(partnerVM.partnerDisplayName.prefix(1)).uppercased())
                            .font(.bodyMedium(14)).foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(partnerVM.partnerDisplayName)
                            .font(.bodyMedium(15)).foregroundColor(.ink)
                        Text(partnerVM.partnerProgressSummaryLine)
                            .font(.caption2).foregroundColor(.muted)
                    }
                    Spacer()
                    Circle()
                        .fill(partnerVM.partnerProgressFraction >= 1.0 ? Color.emeraldGreen : Color.electricOrange)
                        .frame(width: 10, height: 10)
                }

                ProgressView(value: min(partnerVM.partnerProgressFraction, 1.0))
                    .tint(partnerVM.partnerProgressFraction >= 1.0 ? Color.emeraldGreen : Color.electricOrange)

                if let lastSync = partnerVM.lastPartnerSync {
                    HStack(spacing: 4) {
                        if partnerVM.isPartnerDataStale {
                            Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundColor(.amber)
                        }
                        Text("Updated \(lastSync, style: .relative) ago").font(.caption2).foregroundColor(.muted)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.plus").foregroundColor(.muted).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No partner connected").font(.bodyMedium(14)).foregroundColor(.ink)
                        Text("Pair with someone to enable accountability.").font(.caption2).foregroundColor(.muted)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        )
        .padding(.horizontal)
    }
}

// MARK: - Action Button (sscrollBestUI glass style)
struct ActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title).font(.bodyMedium(15))
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.25), lineWidth: 1))
            )
            .foregroundColor(color)
        }
    }
}

// Color(hex:) extension is defined in DesignSystem.swift
