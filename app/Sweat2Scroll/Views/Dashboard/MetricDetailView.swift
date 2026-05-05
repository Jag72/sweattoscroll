// MetricDetailView.swift
// Reusable 30-day drill-in for any health metric on the Trends page.
// Tap a stat card → this view loads the last 30 days from HealthKit, then renders
// a horizontally-scrollable bar chart, summary statistics, and a per-day list.

import SwiftUI
import HealthKit

// MARK: - Metric definition

enum MetricKind: Identifiable {
    case heart
    case steps
    case calories
    case sleep
    case energy(moveGoalKcal: Double)
    case strain

    var id: String { title }

    var title: String {
        switch self {
        case .heart:    return "Heart Rate"
        case .steps:    return "Steps"
        case .calories: return "Active Calories"
        case .sleep:    return "Sleep"
        case .energy:   return "Energy"
        case .strain:   return "Strain"
        }
    }

    var icon: String {
        switch self {
        case .heart:    return "heart.fill"
        case .steps:    return "figure.walk"
        case .calories: return "flame.fill"
        case .sleep:    return "moon.fill"
        case .energy:   return "bolt.fill"
        case .strain:   return "waveform.path.ecg"
        }
    }

    var color: Color {
        switch self {
        case .heart:    return Color(hex: "#FF5A87")
        case .steps:    return Color(hex: "#34C99A")
        case .calories: return .electricOrange
        case .sleep:    return Color(hex: "#A897FF")
        case .energy:   return .electricOrange
        case .strain:   return .amber
        }
    }

    /// Suffix appended after each numeric value (`"\(value)\(unit)"`).
    var unit: String {
        switch self {
        case .heart:    return " bpm"
        case .steps:    return ""
        case .calories: return " kcal"
        case .sleep:    return ""
        case .energy:   return "%"
        case .strain:   return ""
        }
    }

    /// Returns formatted value text (handles k-formatting for steps, h/min for sleep, etc.)
    func format(_ value: Double) -> String {
        switch self {
        case .heart:    return value > 0 ? "\(Int(value))" : "—"
        case .steps:
            if value <= 0 { return "0" }
            return value >= 1000 ? String(format: "%.1fk", value / 1000) : "\(Int(value))"
        case .calories: return "\(Int(value))"
        case .sleep:
            // value in minutes
            let h = Int(value) / 60
            let m = Int(value) % 60
            return value > 0 ? "\(h)h \(m)m" : "—"
        case .energy:   return "\(Int(value))"
        case .strain:   return String(format: "%.1f", value)
        }
    }
}

// MARK: - Detail view

struct MetricDetailView: View {
    let metric: MetricKind
    @Environment(\.dismiss) private var dismiss
    @State private var values: [Double] = []   // 30 days, oldest → today
    @State private var isLoading = true
    /// Index of the currently selected week bucket (defaults to the last/current week)
    @State private var selectedWeek: Int = 0

    /// Date 29 days ago, used as anchor for the per-day list labels.
    private var startDate: Date {
        Calendar.current.date(byAdding: .day, value: -29,
                              to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var nonZeroValues: [Double] { values.filter { $0 > 0 } }
    private var avg: Double { nonZeroValues.isEmpty ? 0 : nonZeroValues.reduce(0, +) / Double(nonZeroValues.count) }
    private var minV: Double { nonZeroValues.min() ?? 0 }
    private var maxV: Double { values.max() ?? 0 }
    private var todayValue: Double { values.last ?? 0 }
    private var totalSum: Double { values.reduce(0, +) }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    chartCard
                    summaryCard
                    if !values.isEmpty && maxV > 0 {
                        weeklyBreakdownCard
                        highlightCards
                        weekComparisonCard
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.ink)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(metric.color.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: metric.icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(metric.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.ink)
                    Text("Last 30 days")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.muted)
                }
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.format(todayValue))
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(.ink)
                Text(metric.unit)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.muted)
                Spacer()
                Text("Today")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(metric.color)
                    .tracking(0.6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Chart card
    private var chartCard: some View {
        DashCard(padding: .init(top: 14, leading: 12, bottom: 14, trailing: 12)) {
            VStack(alignment: .leading, spacing: 10) {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .frame(height: 200)
                } else if values.isEmpty || maxV == 0 {
                    emptyState
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        ScrollViewReader { proxy in
                            HStack(alignment: .bottom, spacing: 6) {
                                ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                                    let h = max(8, CGFloat(value / maxV) * 200)
                                    VStack(spacing: 6) {
                                        Spacer(minLength: 0)
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(metric.color.opacity(idx == values.count - 1 ? 1.0 : 0.85))
                                            .frame(width: 12, height: h)
                                        Text(label(for: idx))
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.muted)
                                            .frame(width: 22)
                                    }
                                    .frame(height: 230)
                                    .id(idx)
                                }
                            }
                            .padding(.horizontal, 8)
                            .onAppear { proxy.scrollTo(values.count - 1, anchor: .trailing) }
                        }
                    }
                    .frame(height: 240)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28))
                .foregroundColor(.muted)
            Text("No data yet for this window")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    // MARK: - Summary
    private var summaryCard: some View {
        DashCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(spacing: 14) {
                summaryRow(label: "Average", value: metric.format(avg))
                Divider()
                summaryRow(label: "Lowest",  value: metric.format(minV))
                Divider()
                summaryRow(label: "Highest", value: metric.format(maxV))
                if showsSum {
                    Divider()
                    summaryRow(label: "30-day total", value: metric.format(totalSum))
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// Sums make sense for cumulative metrics.
    private var showsSum: Bool {
        switch metric {
        case .calories, .steps: return true
        default: return false
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.ink)
                Text(metric.unit.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.muted)
            }
        }
    }

    // MARK: - Weekly buckets

    /// Bucket of `count` consecutive days from `startIndex`. The last bucket is
    /// the current week (today on the right edge).
    private struct WeekBucket: Identifiable {
        let id: Int
        let startIndex: Int
        let count: Int
        let label: String
        let dateRange: String
        let average: Double
        let total: Double
        let bestValue: Double
        let bestDayIndex: Int?
    }

    private var weeklyBuckets: [WeekBucket] {
        let calendar = Calendar.current
        var buckets: [WeekBucket] = []
        let chunkSize = 6
        var index = 0
        var weekNum = 1
        while index < values.count {
            let end = min(index + chunkSize, values.count)
            let slice = Array(values[index..<end])
            let nonZero = slice.filter { $0 > 0 }
            let avg = nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count)
            let total = slice.reduce(0, +)
            let bestVal = slice.max() ?? 0
            let bestRel = slice.firstIndex(of: bestVal)
            let bestAbs = bestRel.map { $0 + index }

            let firstDate = calendar.date(byAdding: .day, value: index, to: startDate) ?? Date()
            let lastDate  = calendar.date(byAdding: .day, value: end - 1, to: startDate) ?? Date()
            let isLast    = end == values.count
            let label     = isLast ? "This wk" : "Wk \(weekNum)"

            buckets.append(WeekBucket(
                id: buckets.count,
                startIndex: index,
                count: slice.count,
                label: label,
                dateRange: rangeLabel(firstDate, lastDate),
                average: avg,
                total: total,
                bestValue: bestVal,
                bestDayIndex: bestAbs
            ))
            index = end
            weekNum += 1
        }
        return buckets
    }

    private var weeklyBreakdownCard: some View {
        let buckets = weeklyBuckets
        let maxAvg = max(buckets.map(\.average).max() ?? 1, 1)
        let activeIndex = min(selectedWeek, max(buckets.count - 1, 0))

        return VStack(spacing: 12) {
            DashCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weekly breakdown")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.ink)
                            Text("Tap a bar to see the day-by-day breakdown")
                                .font(.system(size: 10))
                                .foregroundColor(.muted)
                        }
                        Spacer()
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(buckets) { bucket in
                            weeklyBar(bucket: bucket,
                                      maxAvg: maxAvg,
                                      isActive: bucket.id == activeIndex)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                        selectedWeek = bucket.id
                                    }
                                }
                        }
                    }
                    .frame(height: 145)
                }
            }
            .padding(.horizontal, 20)

            if buckets.indices.contains(activeIndex) {
                weekDetailCard(bucket: buckets[activeIndex])
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func weeklyBar(bucket: WeekBucket, maxAvg: Double, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            Text(metric.format(usesCumulativeForWeekly ? bucket.total : bucket.average))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(isActive ? metric.color : .ink)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(metric.color.opacity(0.12))
                    .frame(height: 90)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(metric.color.opacity(isActive ? 1.0 : 0.55))
                    .frame(height: max(10, CGFloat(bucket.average / maxAvg) * 90))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isActive ? metric.color : Color.clear, lineWidth: 2)
            )
            Text(bucket.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isActive ? metric.color : .muted)
            Text(bucket.dateRange)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// Day-level detail that appears under the weekly bars when a bucket is selected.
    private func weekDetailCard(bucket: WeekBucket) -> some View {
        let dayValues: [(idx: Int, value: Double)] = (0..<bucket.count).map { offset in
            (bucket.startIndex + offset, values[bucket.startIndex + offset])
        }
        let maxV = max(dayValues.map(\.value).max() ?? 1, 1)
        let avgV = bucket.average
        let weekdayLetters = ["S", "M", "T", "W", "T", "F", "S"]
        let calendar = Calendar.current

        return DashCard(padding: .init(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bucket.label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(metric.color)
                        Text(bucket.dateRange)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.ink)
                    }
                    Spacer()
                    weekDetailStat(label: "Avg",
                                   value: metric.format(avgV))
                    if usesCumulativeForWeekly {
                        Divider().frame(height: 30)
                        weekDetailStat(label: "Total",
                                       value: metric.format(bucket.total))
                    } else {
                        Divider().frame(height: 30)
                        weekDetailStat(label: "Best",
                                       value: metric.format(bucket.bestValue))
                    }
                }

                ZStack(alignment: .topLeading) {
                    if avgV > 0 {
                        let normalized = CGFloat(avgV / maxV)
                        GeometryReader { geo in
                            let chartHeight: CGFloat = 110
                            let y = chartHeight - (normalized * chartHeight)
                            HStack(spacing: 4) {
                                Text("avg \(metric.format(avgV))")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.muted)
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.muted.opacity(0.45))
                            }
                            .offset(y: max(0, y - 6))
                            .frame(width: geo.size.width)
                        }
                        .frame(height: 110)
                    }

                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(dayValues, id: \.idx) { item in
                            let isToday = item.idx == values.count - 1
                            let h = max(8, CGFloat(item.value / maxV) * 110)
                            VStack(spacing: 6) {
                                Spacer(minLength: 0)
                                Text(metric.format(item.value))
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(item.value > 0 ? .ink : .muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(metric.color.opacity(isToday ? 1.0 : 0.7))
                                    .frame(height: h)
                                let date = self.date(at: item.idx)
                                let weekday = calendar.component(.weekday, from: date) - 1
                                Text(weekdayLetters[weekday])
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(isToday ? metric.color : .muted)
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.muted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 160)
                }
                .frame(height: 160)
            }
        }
    }

    private func weekDetailStat(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundColor(.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.ink)
                Text(metric.unit.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.muted)
            }
        }
    }

    /// For cumulative metrics like calories and steps, weekly **totals** are more
    /// meaningful than weekly averages.
    private var usesCumulativeForWeekly: Bool {
        switch metric {
        case .calories, .steps: return true
        default: return false
        }
    }

    // MARK: - Highlights (best / worst / today)

    private var highlightCards: some View {
        let bestIdx = values.indices.max { values[$0] < values[$1] }
        let worstIdx = values.indices
            .filter { values[$0] > 0 }
            .min { values[$0] < values[$1] }

        return HStack(spacing: 10) {
            highlightTile(
                title: bestTitle,
                value: bestIdx.map { metric.format(values[$0]) } ?? "—",
                date: bestIdx.map { dateLabel(date(at: $0), short: true) } ?? "—",
                tint: .emeraldGreen,
                icon: "arrow.up.right.circle.fill"
            )
            highlightTile(
                title: worstTitle,
                value: worstIdx.map { metric.format(values[$0]) } ?? "—",
                date: worstIdx.map { dateLabel(date(at: $0), short: true) } ?? "—",
                tint: .rose,
                icon: "arrow.down.right.circle.fill"
            )
        }
        .padding(.horizontal, 20)
    }

    private var bestTitle: String {
        switch metric {
        case .heart:   return "Highest"
        case .strain:  return "Toughest"
        default:       return "Best day"
        }
    }
    private var worstTitle: String {
        switch metric {
        case .heart:   return "Lowest"
        case .strain:  return "Calmest"
        default:       return "Lowest day"
        }
    }

    private func highlightTile(title: String, value: String, date: String,
                               tint: Color, icon: String) -> some View {
        DashCard(padding: .init(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 13)).foregroundColor(tint)
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold)).tracking(0.6)
                        .foregroundColor(tint)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.ink)
                Text(date)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Week-over-week comparison

    private var weekComparisonCard: some View {
        let thisWeek = Array(values.suffix(7))
        let lastWeek = Array(values.dropLast(7).suffix(7))
        let thisAvg = nonZeroAvg(thisWeek)
        let lastAvg = nonZeroAvg(lastWeek)
        let delta = thisAvg - lastAvg
        let pct = lastAvg > 0 ? (delta / lastAvg) * 100 : 0
        let isUp = delta >= 0

        return DashCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("This week vs last week")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.ink)
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(lastAvg > 0
                             ? String(format: "%.0f%%", abs(pct))
                             : "—")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(comparisonColor(isUp: isUp))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(comparisonColor(isUp: isUp).opacity(0.12)))
                }

                HStack(spacing: 14) {
                    comparisonColumn(label: "Last week", value: metric.format(lastAvg), tint: .muted)
                    Divider().frame(height: 30)
                    comparisonColumn(label: "This week", value: metric.format(thisAvg), tint: metric.color)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func comparisonColumn(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundColor(.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                Text(metric.unit.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// For metrics where higher is better (steps/calories/energy), green is up.
    /// For heart rate at rest, lower is generally better — so flip it.
    private func comparisonColor(isUp: Bool) -> Color {
        switch metric {
        case .heart:  return isUp ? .rose : .emeraldGreen
        case .strain: return isUp ? .amber : .emeraldGreen
        default:      return isUp ? .emeraldGreen : .rose
        }
    }

    private func nonZeroAvg(_ arr: [Double]) -> Double {
        let nz = arr.filter { $0 > 0 }
        guard !nz.isEmpty else { return 0 }
        return nz.reduce(0, +) / Double(nz.count)
    }

    private func date(at index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? Date()
    }

    private func dateLabel(_ date: Date, short: Bool = false) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = short ? "MMM d" : "EEE, MMM d"
        return f.string(from: date)
    }

    /// Compact "Mar 4–10" range label. If the start and end dates fall in the
    /// same month, the trailing month name is dropped.
    private func rangeLabel(_ start: Date, _ end: Date) -> String {
        let f = DateFormatter()
        let calendar = Calendar.current
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        f.dateFormat = "MMM d"
        let s = f.string(from: start)
        if sameMonth {
            f.dateFormat = "d"
            return "\(s)–\(f.string(from: end))"
        }
        return "\(s)–\(f.string(from: end))"
    }

    private func label(for idx: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: idx, to: startDate) ?? Date()
        let day = Calendar.current.component(.day, from: date)
        return idx == values.count - 1 ? "T" : "\(day)"
    }

    // MARK: - Data load (per-metric)
    private func load() async {
        isLoading = true
        let hk = HealthKitService.shared
        if !hk.isAuthorized {
            try? await hk.requestAuthorization()
        }

        switch metric {
        case .heart:
            values = await hk.fetchDailyAverageHistory(
                type: .init(.restingHeartRate),
                unit: HKUnit(from: "count/min"),
                days: 30
            )
        case .steps:
            values = await hk.fetchDailySumHistory(
                type: .init(.stepCount), unit: .count(), days: 30
            )
        case .calories:
            values = await hk.fetchDailySumHistory(
                type: .init(.activeEnergyBurned), unit: .kilocalorie(), days: 30
            )
        case .sleep:
            // Returns minutes per day
            values = await hk.fetchDailySleepHistory(days: 30)
        case .energy(let moveGoal):
            // Composite of Move + Exercise + Stand → 0–100 per day
            async let cal   = hk.fetchDailySumHistory(type: .init(.activeEnergyBurned), unit: .kilocalorie(), days: 30)
            async let exMin = hk.fetchDailySumHistory(type: .init(.appleExerciseTime),  unit: .minute(),     days: 30)
            async let stSec = hk.fetchDailySumHistory(type: .init(.appleStandTime),     unit: .second(),     days: 30)
            let (c, e, s) = await (cal, exMin, stSec)
            let safeGoal = max(moveGoal, 100)
            values = (0..<30).map { i in
                let mv  = min((i < c.count ? c[i] : 0) / safeGoal,  1.0)
                let exR = min((i < e.count ? e[i] : 0) / 30.0,      1.0)
                let stR = min((i < s.count ? s[i] / 3600.0 : 0) / 12.0, 1.0)
                return ((mv + exR + stR) / 3.0) * 100
            }
        case .strain:
            // Derived from active calories (0–21 scale)
            let cal = await hk.fetchDailySumHistory(
                type: .init(.activeEnergyBurned), unit: .kilocalorie(), days: 30
            )
            values = cal.map { min($0 / 800.0 * 21.0, 21.0) }
        }

        // Default the selected week to the most recent (current) one.
        selectedWeek = max(weeklyBuckets.count - 1, 0)
        isLoading = false
    }
}
