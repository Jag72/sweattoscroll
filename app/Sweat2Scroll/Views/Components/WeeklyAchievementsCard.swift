// Views/Components/WeeklyAchievementsCard.swift
// "This Week" achievement card shown on the User + Solo home dashboards.
//
// Replaces the old hardcoded "3.2 km / 7-day streak" strip with real,
// HealthKit-driven achievement data:
//   • Days unlocked this week (calorie goal hit → social media unlocked).
//   • Current consecutive-day streak.
//   • Total kcal burned this week + best day.
//   • A weekly bar chart highlighting today.
//   • Up to four milestone badges that light up as the user hits them.

import SwiftUI

/// Pure data model so views stay deterministic and previewable.
struct WeeklyAchievement: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let achieved: Bool
}

struct WeeklyAchievementsCard: View {
    /// 7 daily kcal totals, oldest → today (length 7).
    let calorieHistory: [Double]
    /// Daily calorie goal — the threshold to count a day as "unlocked".
    let dailyGoal: Double
    /// 0..6 index of "today" inside the history array (typically 6).
    var todayIndex: Int = 6
    /// Optional callback when the card is tapped (e.g. open the Trends tab).
    var onTap: (() -> Void)? = nil

    // MARK: - Derived stats

    private var unlockedDays: Int {
        guard dailyGoal > 0 else { return 0 }
        return calorieHistory.filter { $0 >= dailyGoal }.count
    }
    private var totalKcal: Double { calorieHistory.reduce(0, +) }
    private var bestKcal: Double { calorieHistory.max() ?? 0 }
    private var bestDayLabel: String {
        guard let idx = calorieHistory.firstIndex(of: bestKcal), bestKcal > 0 else { return "—" }
        return Self.dayLabels[idx]
    }
    /// Walks back from today; counts consecutive days the goal was met.
    private var currentStreak: Int {
        guard dailyGoal > 0 else { return 0 }
        var streak = 0
        for i in stride(from: todayIndex, through: 0, by: -1) {
            if calorieHistory[i] >= dailyGoal { streak += 1 }
            else { break }
        }
        return streak
    }

    private var achievements: [WeeklyAchievement] {
        let progress = unlockedDays
        return [
            WeeklyAchievement(
                id: "first-unlock",
                icon: "lock.open.fill",
                title: "First unlock",
                subtitle: "Earned your scroll once",
                tint: .electricOrange,
                achieved: progress >= 1
            ),
            WeeklyAchievement(
                id: "streak-3",
                icon: "flame.fill",
                title: "3-day streak",
                subtitle: "Three goals in a row",
                tint: .amber,
                achieved: currentStreak >= 3
            ),
            WeeklyAchievement(
                id: "five-days",
                icon: "rosette",
                title: "Weekday warrior",
                subtitle: "Unlocked 5 days",
                tint: .emeraldGreen,
                achieved: progress >= 5
            ),
            WeeklyAchievement(
                id: "perfect-week",
                icon: "crown.fill",
                title: "Perfect week",
                subtitle: "All 7 days earned",
                tint: .deepTeal,
                achieved: progress >= 7
            )
        ]
    }

    // MARK: - View

    var body: some View {
        Button(action: { onTap?() }) {
            content
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    @ViewBuilder
    private var content: some View {
        DashCard {
            VStack(alignment: .leading, spacing: 16) {
                header
                statsRow
                weekBars
                if !achievements.isEmpty {
                    Divider().opacity(0.4)
                    achievementsRow
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.muted)
                    .tracking(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(unlockedDays)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.ink)
                    Text("/ 7 days unlocked")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.muted)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.electricOrange)
                Text("\(currentStreak)-day streak")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.electricOrange)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.electricOrange.opacity(0.12)))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(value: "\(Int(totalKcal))", unit: "kcal", label: "Total burned")
            Divider().frame(height: 30)
            statColumn(value: "\(Int(bestKcal))", unit: "kcal", label: "Best (\(bestDayLabel))")
            Divider().frame(height: 30)
            statColumn(value: "\(unlockedDays)", unit: "days", label: "Unlocks")
        }
    }

    private func statColumn(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.ink)
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.muted)
            }
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.muted)
                .tracking(0.4)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekBars: some View {
        let maxV = max(dailyGoal, calorieHistory.max() ?? dailyGoal, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let v = calorieHistory.indices.contains(i) ? calorieHistory[i] : 0
                let met = dailyGoal > 0 && v >= dailyGoal
                let isToday = i == todayIndex
                let h = max(8.0, CGFloat(min(v / maxV, 1.0)) * 44.0)
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(barColor(met: met, isToday: isToday))
                        .frame(height: h)
                        .overlay(
                            isToday ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.electricOrange, lineWidth: 1.5) : nil
                        )
                    Text(Self.dayLabels[i])
                        .font(.system(size: 9, weight: isToday ? .bold : .medium))
                        .foregroundColor(isToday ? .electricOrange : .muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 60)
    }

    private func barColor(met: Bool, isToday: Bool) -> Color {
        if isToday { return .electricOrange }
        if met     { return .emeraldGreen.opacity(0.7) }
        return .rose.opacity(0.25)
    }

    private var achievementsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACHIEVEMENTS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.muted)
                .tracking(0.8)
            HStack(spacing: 8) {
                ForEach(achievements) { item in
                    achievementBadge(item)
                }
            }
        }
    }

    private func achievementBadge(_ item: WeeklyAchievement) -> some View {
        let tint = item.tint
        let active = item.achieved
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(active ? tint.opacity(0.16) : Color.ringTrack.opacity(0.45))
                    .frame(width: 40, height: 40)
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(active ? tint : .muted.opacity(0.55))
            }
            Text(item.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(active ? .ink : .muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .opacity(active ? 1 : 0.7)
    }

    // MARK: - Day labels (Mon..Sun, today expected at index 6)
    private static let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
}
