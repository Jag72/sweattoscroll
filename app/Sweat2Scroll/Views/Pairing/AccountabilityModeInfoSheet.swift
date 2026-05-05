// Views/Pairing/AccountabilityModeInfoSheet.swift
// Bottom sheet shown when the user taps one of the "Mutual accountability /
// Emergency override / Parent · coach mode" perk cards on the onboarding
// pairing prompt (or any future entry point that wants to surface partner
// info contextually).
//
// Three jobs:
//   1. Explain what the mode is, in plain English.
//   2. Show the live list of connected partners with each partner's progress
//      toward their daily goal as a percentage.
//   3. If the user has nobody connected yet, surface the "Generate code" /
//      "Enter code" pairing flows inline so they can act immediately.

import SwiftUI

struct AccountabilityModeInfoSheet: View {
    enum Mode: Identifiable {
        case mutual, override, controller

        var id: String {
            switch self {
            case .mutual: return "mutual"
            case .override: return "override"
            case .controller: return "controller"
            }
        }
        var icon: String {
            switch self {
            case .mutual: return "person.2.fill"
            case .override: return "key.fill"
            case .controller: return "person.crop.circle.badge.checkmark"
            }
        }
        var tint: Color {
            switch self {
            case .mutual: return .deepTeal
            case .override: return .electricOrange
            case .controller: return .amber
            }
        }
        var title: String {
            switch self {
            case .mutual: return "Mutual accountability"
            case .override: return "Emergency override"
            case .controller: return "Parent / coach mode"
            }
        }
        var headline: String {
            switch self {
            case .mutual:
                return "Both burn calories, both stay honest."
            case .override:
                return "Stuck on a sick day? Your partner sends you an OTP."
            case .controller:
                return "One-way control — you set the rules, they earn the unlock."
            }
        }
        var bullets: [String] {
            switch self {
            case .mutual:
                return [
                    "Both phones track activity through HealthKit.",
                    "Apps unlock only when each side hits their own daily goal.",
                    "Either partner can grant the other an emergency override."
                ]
            case .override:
                return [
                    "You set how many minutes the unlock lasts (5–240 min).",
                    "App generates a fresh 6-digit code; share it with your partner.",
                    "They type it into their phone to drop the shield instantly."
                ]
            case .controller:
                return [
                    "You're the parent / coach — your phone isn't blocked.",
                    "You set the daily goal for the person you're monitoring.",
                    "You issue override OTPs whenever they need a break."
                ]
            }
        }
    }

    let mode: Mode
    @ObservedObject var partnerVM: PartnerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pairingRoute: PairingRoute?

    private enum PairingRoute: String, Identifiable {
        case generate, enter
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    bulletList
                    Divider().padding(.top, 4)
                    partnerSection
                }
                .padding(20)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.electricOrange)
                }
            }
        }
        .sheet(item: $pairingRoute) { route in
            NavigationStack {
                switch route {
                case .generate: PairCodeGeneratorView()
                case .enter:    PairCodeEntryView()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(mode.tint.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: mode.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(mode.tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.ink)
                Text(mode.headline)
                    .font(.system(size: 13))
                    .foregroundColor(.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var bulletList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(mode.bullets, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.emeraldGreen)
                        .padding(.top, 1)
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundColor(.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Partner section

    @ViewBuilder
    private var partnerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CONNECTED PARTNERS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.muted)
                    .tracking(0.8)
                Spacer()
                if partnerVM.isPartnerPaired {
                    Button {
                        Task { await partnerVM.refreshPartnerData() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: partnerVM.isSyncing
                                  ? "arrow.triangle.2.circlepath"
                                  : "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text(partnerVM.isSyncing ? "Syncing…" : "Refresh")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.electricOrange)
                    }
                    .disabled(partnerVM.isSyncing)
                }
            }

            if partnerVM.isPartnerPaired {
                connectedPartnerCard
            } else {
                emptyState
            }
        }
    }

    private var connectedPartnerCard: some View {
        let pct = Int((partnerVM.partnerProgressFraction * 100).rounded())
        let metGoal = partnerVM.partnerProgressFraction >= 1.0
        let display = partnerVM.partnerDisplayName.isEmpty ? "Partner" : partnerVM.partnerDisplayName
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(mode.tint)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(display.prefix(1)).uppercased())
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Circle()
                        .fill(metGoal ? Color.emeraldGreen : Color.amber)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(display)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.ink)
                    Text(partnerVM.partnerProgressSummaryLine)
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                }
                Spacer()
                Text("\(pct)%")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(metGoal ? .emeraldGreen : .electricOrange)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.ringTrack.opacity(0.6))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(metGoal ? Color.emeraldGreen : Color.electricOrange)
                        .frame(width: geo.size.width * partnerVM.partnerProgressFraction, height: 10)
                }
            }
            .frame(height: 10)

            if let last = partnerVM.lastPartnerSync {
                let formatter: RelativeDateTimeFormatter = {
                    let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
                }()
                Text("Last update \(formatter.localizedString(for: last, relativeTo: Date()))")
                    .font(.system(size: 11))
                    .foregroundColor(.muted)
            } else {
                Text("Waiting for partner to sync their progress…")
                    .font(.system(size: 11))
                    .foregroundColor(.muted)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 30))
                    .foregroundColor(.muted.opacity(0.5))
                Text("No partners connected yet")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.ink)
                Text("Pair a phone to see live progress here.")
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)

            Button { pairingRoute = .generate } label: {
                Text("I'll generate a code")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.electricOrange)
                    )
            }
            Button { pairingRoute = .enter } label: {
                Text("I have a code from my partner")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.electricOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.electricOrange, lineWidth: 1.5)
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}
