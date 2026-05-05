// Views/Components/BlockingFlowViews.swift
// Solo "earn-your-scroll" UI — banner, full-screen block, justification sheet,
// and day-bypass reflection sheet. All powered by `BlockingSessionService`.

import SwiftUI

// MARK: - Status Banner
// Replaces the legacy `AppShieldBanner` on the Solo home screen. The banner
// summarizes the current `BlockingPhase`, and is tappable while blocked so
// the user can open the in-app shield with the bypass actions.
struct BlockingStatusBanner: View {
    let phase: BlockingPhase
    let kcalRemaining: Int
    let graceMinutes: Int
    let bypassMinutes: Int
    var onTapBlocked: () -> Void = {}

    private var color: Color {
        switch phase {
        case .blocked:                  return .rose
        case .unlocked, .dayBypass:     return .emeraldGreen
        case .bypass15:                 return .amber
        case .grace:                    return .deepTeal
        case .idle:                     return .muted
        }
    }

    private var icon: String {
        switch phase {
        case .blocked:   return "lock.fill"
        case .unlocked:  return "checkmark.circle.fill"
        case .grace:     return "clock.fill"
        case .bypass15:  return "hourglass"
        case .dayBypass: return "calendar.badge.exclamationmark"
        case .idle:      return "app.badge"
        }
    }

    private var title: String {
        switch phase {
        case .blocked:   return "Apps blocked — burn to unlock"
        case .unlocked:  return "Goal met — apps unlocked"
        case .grace:     return "Free scroll window"
        case .bypass15:  return "15-min bypass active"
        case .dayBypass: return "Apps unlocked for today"
        case .idle:      return "No apps to lock yet"
        }
    }

    private var subtitle: String {
        switch phase {
        case .blocked:
            return "\(kcalRemaining) kcal to earn your scroll • Tap"
        case .unlocked:
            return "You earned your scroll."
        case .grace:
            return "\(graceMinutes) min of free time left"
        case .bypass15:
            return "\(bypassMinutes) min until apps re-lock"
        case .dayBypass:
            return "Resets at midnight"
        case .idle:
            return "Pick apps from Profile → Restricted Apps"
        }
    }

    var body: some View {
        Button {
            if phase == .blocked { onTapBlocked() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(color)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                }
                Spacer()
                if phase == .blocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(color.opacity(0.18), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - In-App Block Screen
// Full-screen cover that mirrors the OS shield, but with full action surface:
// "I'll go burn it", "Use 15 minutes" (→ justification), and once a note has
// been written, "Unlock for the rest of today" (→ reflection sheet).
struct AppBlockedShieldView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session = BlockingSessionService.shared

    let kcalBurned: Int
    let kcalGoal: Int
    var onRequestFifteenMinuteBypass: (String) -> Void = { _ in }
    var onRequestDayBypass: () -> Void = {}

    @State private var showJustification = false
    @State private var showDayConfirm = false

    private var remaining: Int { max(0, kcalGoal - kcalBurned) }
    private var progress: Double {
        guard kcalGoal > 0 else { return 0 }
        return min(Double(kcalBurned) / Double(kcalGoal), 1.0)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#0F0F12"), Color(hex: "#1B1B22")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    closeButton
                        .padding(.top, 12)

                    Sweat2ScrollLogo(size: 92, transparentBackground: true, animated: true)
                        .shadow(color: Color.electricOrange.opacity(0.55),
                                radius: 26)

                    VStack(spacing: 6) {
                        Text("SWEAT2SCROLL")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(2.4)
                            .foregroundColor(.electricOrange)
                        Text("Earn your scroll")
                            .font(.system(size: 30, weight: .black))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 4)

                    progressRing
                    statRow
                    actions
                    if !session.procrastinationNote.isEmpty {
                        priorNoteCard
                    }
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showJustification) {
            JustificationNoteSheet { note in
                onRequestFifteenMinuteBypass(note)
                showJustification = false
                dismiss()
            }
        }
        .sheet(isPresented: $showDayConfirm) {
            DayUnlockReflectionSheet(
                priorNote: session.procrastinationNote,
                noteAt: session.procrastinationNoteAt
            ) {
                onRequestDayBypass()
                showDayConfirm = false
                dismiss()
            }
        }
    }

    // MARK: - Pieces

    private var closeButton: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), lineWidth: 14)
                .frame(width: 200, height: 200)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color.electricOrange, Color(hex: "#FF8E59")],
                        startPoint: .top, endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 200, height: 200)
            VStack(spacing: 2) {
                Text("\(remaining)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                Text("KCAL TO GO")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private var statRow: some View {
        HStack(spacing: 0) {
            statBlock(big: "\(kcalBurned)", label: "BURNED")
            divider
            statBlock(big: "\(kcalGoal)", label: "GOAL")
            divider
            statBlock(big: "\(Int(progress * 100))%", label: "DONE")
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 32)
    }

    private func statBlock(big: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(big)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                    Text("I'll go burn it")
                }
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.electricOrange, Color(hex: "#FF8E59")],
                            startPoint: .leading, endPoint: .trailing
                        ))
                )
                .shadow(color: Color.electricOrange.opacity(0.45), radius: 18, y: 8)
            }

            Button { showJustification = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                    Text("Use for 15 minutes")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.78))
                .frame(maxWidth: .infinity).frame(height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
            }

            if !session.procrastinationNote.isEmpty {
                Button { showDayConfirm = true } label: {
                    Text("Unlock for the rest of today")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .underline()
                }
                .padding(.top, 4)
            }
        }
    }

    private var priorNoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("YOU WROTE EARLIER", systemImage: "quote.opening")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.45))
            Text("\u{201C}\(session.procrastinationNote)\u{201D}")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
                .lineLimit(3)
            if let at = session.procrastinationNoteAt {
                Text(relativeTimeString(at))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        Text("Restricted by Sweat2Scroll • Resets at midnight")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.32))
            .padding(.top, 4)
    }
}

// MARK: - Justification Note Sheet
// Forces the user to articulate WHY they want to procrastinate before the
// 15-min bypass is granted. The note is replayed back to them later if they
// try to unlock for the entire day.
struct JustificationNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSubmit: (String) -> Void

    @State private var note: String = ""
    @FocusState private var focused: Bool
    private let minChars = 25

    private var trimmed: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSubmit: Bool { trimmed.count >= minChars }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    editor
                    counter
                    submitButton
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Justify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(.electricOrange)
                }
            }
            .onAppear { focused = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.electricOrange.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.electricOrange)
                }
                Text("15-MIN BYPASS")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.6)
                    .foregroundColor(.electricOrange)
            }
            Text("Tell yourself why")
                .font(.system(size: 28, weight: .black))
                .foregroundColor(.ink)
            Text("Write down what's pulling you to scroll instead of move. We'll show this back to you if you try to unlock the whole day later.")
                .font(.system(size: 14))
                .foregroundColor(.muted)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if note.isEmpty {
                Text("e.g. I just want to numb out for a bit, even though I know I'll feel worse after…")
                    .font(.system(size: 15))
                    .foregroundColor(.muted.opacity(0.55))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
            TextEditor(text: $note)
                .focused($focused)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(minHeight: 160, maxHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.muted.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.muted.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var counter: some View {
        HStack(spacing: 6) {
            Image(systemName: canSubmit ? "checkmark.seal.fill" : "circle.dashed")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(canSubmit ? .emeraldGreen : .muted)
            Text("\(trimmed.count) / \(minChars) characters")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(canSubmit ? .emeraldGreen : .muted)
            Spacer()
        }
    }

    private var submitButton: some View {
        Button {
            onSubmit(trimmed)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                Text("Unlock for 15 minutes")
            }
            .font(.system(size: 16, weight: .heavy))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(canSubmit ? Color.electricOrange : Color.muted.opacity(0.4))
            )
            .shadow(color: canSubmit ? Color.electricOrange.opacity(0.35) : .clear,
                    radius: 14, y: 6)
        }
        .disabled(!canSubmit)
    }
}

// MARK: - Day Unlock Reflection Sheet
// Replays the user's earlier procrastination note as a friction mirror before
// granting an all-day bypass.
struct DayUnlockReflectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let priorNote: String
    let noteAt: Date?
    var onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    noteCard
                    confirmCopy
                    confirmButton
                    cancelButton
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .tint(.electricOrange)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.electricOrange.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: "quote.opening")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.electricOrange)
                }
                Text("YOUR EARLIER NOTE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.6)
                    .foregroundColor(.electricOrange)
            }
            Text("Read this back to yourself")
                .font(.system(size: 26, weight: .black))
                .foregroundColor(.ink)
            Text("Before unlocking apps for the rest of the day, sit with what you wrote earlier.")
                .font(.system(size: 14))
                .foregroundColor(.muted)
        }
    }

    private var noteCard: some View {
        DashCard(padding: .init(top: 18, leading: 18, bottom: 18, trailing: 18)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\u{201C}\(priorNote)\u{201D}")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let at = noteAt {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.muted)
                        Text("Written \(relativeTimeString(at))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.muted)
                    }
                }
            }
        }
    }

    private var confirmCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Still want to unlock?")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.ink)
            Text("Apps will stay open until midnight, even if you don't hit your calorie goal today.")
                .font(.system(size: 13))
                .foregroundColor(.muted)
        }
    }

    private var confirmButton: some View {
        Button {
            onConfirm()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                Text("Yes, unlock until midnight")
            }
            .font(.system(size: 16, weight: .heavy))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.electricOrange)
            )
            .shadow(color: Color.electricOrange.opacity(0.35), radius: 14, y: 6)
        }
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "figure.run")
                Text("Stay locked — I'll go move")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.electricOrange)
            .frame(maxWidth: .infinity).frame(height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.electricOrange.opacity(0.4), lineWidth: 1.5)
            )
        }
    }
}
