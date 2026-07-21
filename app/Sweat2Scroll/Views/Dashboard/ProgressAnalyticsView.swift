// Views/Dashboard/ProgressAnalyticsView.swift
// Interactive analytics: Swift Charts with D / W / M / 6M ranges, drag-to-scrub
// inspection, previous-period ghost overlay, personal-baseline bands, and
// auto-generated insight cards. Self-loading — reads HealthKit directly and
// scores through `WellnessAlgorithms`.

import SwiftUI
import Charts
import HealthKit

// MARK: - Chart data model

struct AnalyticsPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let isCurrent: Bool     // false → previous-period ghost series
}

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case day = "D", week = "W", month = "M", sixMonths = "6M"
    var id: String { rawValue }

    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 182
        }
    }
    var comparisonLabel: String {
        switch self {
        case .day: return "vs yesterday"
        case .week: return "vs last week"
        case .month: return "vs last month"
        case .sixMonths: return "vs prior 6 months"
        }
    }
}

enum AnalyticsMetric: String, CaseIterable, Identifiable {
    case calories = "Calories"
    case steps = "Steps"
    case heart = "Heart"
    case hrv = "HRV"
    case sleep = "Sleep"
    case energy = "Energy"
    case strain = "Strain"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .calories: return "flame.fill"
        case .steps: return "figure.walk"
        case .heart: return "heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .sleep: return "moon.fill"
        case .energy: return "bolt.fill"
        case .strain: return "gauge.high"
        }
    }
    var color: Color {
        switch self {
        case .calories: return .electricOrange
        case .steps: return Color(hex: "#34C99A")
        case .heart: return Color(hex: "#FF5A87")
        case .hrv: return Color(hex: "#7B61FF")
        case .sleep: return Color(hex: "#A897FF")
        case .energy: return .amber
        case .strain: return Color(hex: "#FF8C42")
        }
    }
    var unit: String {
        switch self {
        case .calories: return "kcal"
        case .steps: return "steps"
        case .heart, .hrv: return rawValue == "HRV" ? "ms" : "bpm"
        case .sleep: return "hrs"
        case .energy: return "%"
        case .strain: return ""
        }
    }
    /// Bars for cumulative metrics, line+area for continuous biometrics.
    var isCumulative: Bool {
        switch self {
        case .calories, .steps, .strain: return true
        case .heart, .hrv, .sleep, .energy: return false
        }
    }
    /// Whether an increase is good (drives delta-chip color).
    var higherIsBetter: Bool {
        switch self {
        case .heart, .strain: return false
        default: return true
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .steps:
            return v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))"
        case .sleep:
            let h = Int(v) / 60, m = Int(v) % 60
            return v > 0 ? "\(h)h \(m)m" : "—"
        case .strain:
            return String(format: "%.1f", v)
        default:
            return v > 0 ? "\(Int(v))" : "—"
        }
    }
}

// MARK: - View

struct ProgressAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    var moveGoalKcal: Double = 500

    @State private var metric: AnalyticsMetric = .calories
    @State private var range: AnalyticsRange = .week
    @State private var points: [AnalyticsPoint] = []
    @State private var isLoading = true
    @State private var selectedPoint: AnalyticsPoint?
    @State private var baseline: MetricBaseline = .from([])
    @State private var insights: [WellnessAlgorithms.Insight] = []
    @State private var loadTask: Task<Void, Never>?

    private var currentPoints: [AnalyticsPoint] { points.filter(\.isCurrent) }
    private var ghostPoints: [AnalyticsPoint] { points.filter { !$0.isCurrent } }

    private var currentAvg: Double { nonZeroAvg(currentPoints.map(\.value)) }
    private var previousAvg: Double { nonZeroAvg(ghostPoints.map(\.value)) }
    private var currentTotal: Double { currentPoints.map(\.value).reduce(0, +) }
    private var bestValue: Double { currentPoints.map(\.value).max() ?? 0 }

    private var deltaPct: Double? {
        guard previousAvg > 0, currentAvg > 0 else { return nil }
        return (currentAvg - previousAvg) / previousAvg * 100
    }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    metricChips
                    header
                    rangePicker
                    chartCard
                    statStrip
                    if !insights.isEmpty { insightsSection }
                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.foregroundColor(.electricOrange)
            }
        }
        .task { reload() }
        .onChange(of: metric) { _ in reload() }
        .onChange(of: range) { _ in reload() }
    }

    // MARK: - Metric chips

    private var metricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnalyticsMetric.allCases) { m in
                    Button {
                        HapticEngine.impact(.light)
                        metric = m
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: m.icon).font(.system(size: 11, weight: .semibold))
                            Text(m.rawValue).font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(metric == m ? .white : .ink)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(
                            Capsule().fill(metric == m ? m.color : Color.white)
                        )
                        .overlay(
                            Capsule().strokeBorder(metric == m ? Color.clear : Color.ringTrack, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(headlineValue)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(.ink)
                    .contentTransition(.numericText())
                Text(metric.unit)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.muted)
                Spacer()
                if let pct = deltaPct {
                    deltaChip(pct)
                }
            }
            Text(headlineCaption)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.muted)
        }
        .padding(.horizontal, 20)
    }

    private var headlineValue: String {
        if let sel = selectedPoint { return metric.format(sel.value) }
        switch range {
        case .day: return metric.format(currentPoints.last?.value ?? 0)
        default: return metric.isCumulative && range != .sixMonths
            ? metric.format(currentAvg)
            : metric.format(currentAvg)
        }
    }

    private var headlineCaption: String {
        if let sel = selectedPoint {
            let f = DateFormatter()
            f.dateFormat = range == .day ? "h a" : "EEE, MMM d"
            return f.string(from: sel.date)
        }
        switch range {
        case .day: return "Latest today"
        case .week: return "Daily average · last 7 days"
        case .month: return "Daily average · last 30 days"
        case .sixMonths: return "Weekly average · last 6 months"
        }
    }

    private func deltaChip(_ pct: Double) -> some View {
        let improving = metric.higherIsBetter ? pct >= 0 : pct <= 0
        return HStack(spacing: 3) {
            Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text(String(format: "%.0f%%", abs(pct)))
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(improving ? .emeraldGreen : .rose)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill((improving ? Color.emeraldGreen : Color.rose).opacity(0.12)))
    }

    // MARK: - Range picker

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(AnalyticsRange.allCases) { r in Text(r.rawValue).tag(r) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    // MARK: - Chart

    private var chartCard: some View {
        DashCard(padding: .init(top: 16, leading: 12, bottom: 12, trailing: 12)) {
            Group {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 240)
                } else if currentPoints.allSatisfy({ $0.value == 0 }) {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        chart.frame(height: 250)
                        if !metric.isCumulative, !ghostPoints.isEmpty {
                            chartLegend
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// Horizontal line shape for the dashed legend swatch.
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }

    /// Tiny legend shown only when the previous-period ghost line is drawn,
    /// so the dashed grey line is never a mystery.
    private var chartLegend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Capsule().fill(metric.color).frame(width: 16, height: 3)
                Text("This period")
            }
            HStack(spacing: 5) {
                Line()
                    .stroke(Color.muted.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: 16, height: 2)
                Text("Last period")
            }
            Spacer()
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.muted)
        .padding(.horizontal, 6)
    }

    private var chart: some View {
        Chart {
            // Personal baseline band (biometrics only, when reliable).
            if !metric.isCumulative, baseline.isReliable, range != .day {
                RectangleMark(
                    yStart: .value("Baseline low", baseline.mean - baseline.sd),
                    yEnd:   .value("Baseline high", baseline.mean + baseline.sd)
                )
                .foregroundStyle(metric.color.opacity(0.07))
                RuleMark(y: .value("Baseline", baseline.mean))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(metric.color.opacity(0.45))
                    .annotation(position: .topTrailing) {
                        Text("baseline")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(metric.color.opacity(0.6))
                    }
            }

            // Previous-period ghost — biometric line charts only. Overlaying a
            // dashed spline on bar charts read as unlabeled noise, and the
            // week-over-week delta is already shown in the header chip and
            // insights. `.monotone` never overshoots the actual data points
            // (catmullRom drew huge phantom arcs between spiky days).
            if !metric.isCumulative {
                ForEach(ghostPoints.filter { $0.value > 0 }) { p in
                    LineMark(
                        x: .value("Date", p.date, unit: xUnit),
                        y: .value("Prev", p.value),
                        series: .value("Series", "previous")
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(Color.muted.opacity(0.45))
                }
            }

            // Current period.
            if metric.isCumulative {
                ForEach(currentPoints) { p in
                    BarMark(
                        x: .value("Date", p.date, unit: xUnit),
                        y: .value(metric.rawValue, p.value)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(
                        selectedPoint == nil || selectedPoint?.id == p.id
                            ? metric.color.gradient
                            : metric.color.opacity(0.35).gradient
                    )
                }
            } else {
                ForEach(currentPoints.filter { $0.value > 0 }) { p in
                    AreaMark(
                        x: .value("Date", p.date, unit: xUnit),
                        y: .value(metric.rawValue, p.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [metric.color.opacity(0.28), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(
                        x: .value("Date", p.date, unit: xUnit),
                        y: .value(metric.rawValue, p.value),
                        series: .value("Series", "current")
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(metric.color)
                    PointMark(
                        x: .value("Date", p.date, unit: xUnit),
                        y: .value(metric.rawValue, p.value)
                    )
                    .symbolSize(selectedPoint?.id == p.id ? 90 : 26)
                    .foregroundStyle(metric.color)
                }
            }

            // Average rule.
            if currentAvg > 0, range != .day {
                RuleMark(y: .value("Average", currentAvg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(Color.ink.opacity(0.35))
                    .annotation(position: .bottomTrailing) {
                        Text("avg \(metric.format(currentAvg))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.muted)
                    }
            }

            // Goal line for calories.
            if metric == .calories, moveGoalKcal > 0, range != .day {
                RuleMark(y: .value("Goal", moveGoalKcal))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                    .foregroundStyle(Color.emeraldGreen.opacity(0.7))
                    .annotation(position: .topLeading) {
                        Text("goal")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.emeraldGreen)
                    }
            }

            // Selection indicator.
            if let sel = selectedPoint {
                RuleMark(x: .value("Selected", sel.date, unit: xUnit))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.ink.opacity(0.3))
                    .annotation(position: .top) {   // (overflowResolution needs iOS 17 — keep 16-compatible)
                        VStack(spacing: 1) {
                            Text(metric.format(sel.value))
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(.ink)
                            Text(annotationDate(sel.date))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.muted)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                        )
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .sixMonths ? 6 : 5)) { _ in
                AxisGridLine().foregroundStyle(Color.ringTrack.opacity(0.6))
                AxisValueLabel(format: xAxisFormat)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.ringTrack.opacity(0.6))
                AxisValueLabel()
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.muted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let origin = geo[proxy.plotAreaFrame].origin
                                let x = drag.location.x - origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                let nearest = currentPoints.min {
                                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                }
                                if nearest?.id != selectedPoint?.id {
                                    selectedPoint = nearest
                                    HapticEngine.impact(.light)
                                }
                            }
                            .onEnded { _ in
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                                    await MainActor.run { selectedPoint = nil }
                                }
                            }
                    )
            }
        }
    }

    private var xUnit: Calendar.Component {
        switch range {
        case .day: return .hour
        case .sixMonths: return .weekOfYear
        default: return .day
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch range {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day().month(.abbreviated)
        case .sixMonths: return .dateTime.month(.abbreviated)
        }
    }

    private func annotationDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = range == .day ? "h a" : "MMM d"
        return f.string(from: d)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 30)).foregroundColor(.muted.opacity(0.5))
            Text("No \(metric.rawValue.lowercased()) data in this window")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.muted)
            Text("Data appears automatically as Apple Health records it.")
                .font(.system(size: 11)).foregroundColor(.muted.opacity(0.8))
        }
        .frame(maxWidth: .infinity).frame(height: 220)
    }

    // MARK: - Stat strip

    private var statStrip: some View {
        HStack(spacing: 10) {
            statTile(label: rangeStatLabel, value: metric.format(currentAvg))
            statTile(label: "Best", value: metric.format(bestValue))
            if metric.isCumulative {
                statTile(label: "Total", value: metric.format(currentTotal))
            } else {
                statTile(label: baseline.isReliable ? "Baseline" : "Prev avg",
                         value: metric.format(baseline.isReliable ? baseline.mean : previousAvg))
            }
        }
        .padding(.horizontal, 20)
    }

    private var rangeStatLabel: String {
        range == .day ? "Today" : "Average"
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundColor(.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 6, y: 1)
        )
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INSIGHTS")
                .font(.system(size: 11, weight: .bold)).tracking(0.9)
                .foregroundColor(.muted)
                .padding(.horizontal, 20)
            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill((insight.isPositive ? Color.emeraldGreen : Color.amber).opacity(0.13))
                            .frame(width: 34, height: 34)
                        Image(systemName: insight.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(insight.isPositive ? .emeraldGreen : .amber)
                    }
                    Text(insight.text)
                        .font(.system(size: 13))
                        .foregroundColor(.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 1)
                )
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Data loading

    private func reload() {
        loadTask?.cancel()
        selectedPoint = nil
        isLoading = true
        loadTask = Task {
            let (pts, base) = await loadSeries(metric: metric, range: range)
            let ins = await loadInsights()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                points = pts
                baseline = base
                insights = ins
                isLoading = false
            }
        }
    }

    /// Fetches current + previous period values and maps them onto overlapping
    /// dates so the ghost series aligns with the current one on the x-axis.
    private func loadSeries(metric: AnalyticsMetric,
                            range: AnalyticsRange) async -> ([AnalyticsPoint], MetricBaseline) {
        let hk = HealthKitService.shared
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        // "Day" range → hourly, no ghost (yesterday shown via delta only).
        if range == .day {
            let hourly: [Double]
            switch metric {
            case .calories: hourly = await hk.fetchHourlySumToday(type: .init(.activeEnergyBurned), unit: .kilocalorie())
            case .steps:    hourly = await hk.fetchHourlySumToday(type: .init(.stepCount), unit: .count())
            case .heart:    hourly = await hk.fetchHourlyAverageToday(type: .init(.heartRate), unit: HKUnit(from: "count/min"))
            case .hrv:      hourly = await hk.fetchHourlyAverageToday(type: .init(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli))
            default:
                // Sleep/energy/strain don't have meaningful hourly shapes — show week.
                return await loadSeries(metric: metric, range: .week)
            }
            let currentHour = calendar.component(.hour, from: Date())
            let pts = hourly.prefix(currentHour + 1).enumerated().map { (h, v) in
                AnalyticsPoint(date: calendar.date(byAdding: .hour, value: h, to: todayStart)!,
                               value: v, isCurrent: true)
            }
            return (pts, .from([]))
        }

        // Daily (or weekly for 6M) values covering both periods.
        let window = range.days * 2
        let raw = await fetchDaily(metric: metric, days: window, hk: hk)

        // Baseline over the trailing 30 days (biometrics).
        let baselineWindow = Array(raw.suffix(30))
        let base = MetricBaseline.from(baselineWindow)

        let startDate = calendar.date(byAdding: .day, value: -(window - 1), to: todayStart)!
        var pts: [AnalyticsPoint] = []

        if range == .sixMonths {
            // Weekly buckets: 26 current + 26 ghost.
            let weeks = raw.chunked(into: 7).map { nonZeroAvg($0) }
            let half = weeks.count / 2
            for (i, v) in weeks.enumerated() {
                let isCurrent = i >= half
                // Ghost weeks are shifted forward so they overlay current weeks.
                let displayIndex = isCurrent ? i - half : i
                let date = calendar.date(byAdding: .day, value: displayIndex * 7 + 3,
                                         to: calendar.date(byAdding: .day, value: half * 7, to: startDate)!)!
                pts.append(AnalyticsPoint(date: date, value: v, isCurrent: isCurrent))
            }
        } else {
            let half = raw.count / 2
            for (i, v) in raw.enumerated() {
                let isCurrent = i >= half
                let displayOffset = isCurrent ? i : i + half   // shift ghost onto current dates
                let date = calendar.date(byAdding: .day, value: displayOffset, to: startDate)!
                pts.append(AnalyticsPoint(date: date, value: v, isCurrent: isCurrent))
            }
        }
        return (pts, base)
    }

    private func fetchDaily(metric: AnalyticsMetric, days: Int, hk: HealthKitService) async -> [Double] {
        switch metric {
        case .calories:
            return await hk.fetchDailySumHistory(type: .init(.activeEnergyBurned), unit: .kilocalorie(), days: days)
        case .steps:
            return await hk.fetchDailySumHistory(type: .init(.stepCount), unit: .count(), days: days)
        case .heart:
            return await hk.fetchDailyAverageHistory(type: .init(.restingHeartRate), unit: HKUnit(from: "count/min"), days: days)
        case .hrv:
            return await hk.fetchDailyAverageHistory(type: .init(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), days: days)
        case .sleep:
            return await hk.fetchDailySleepHistory(days: days)
        case .energy:
            async let cal = hk.fetchDailySumHistory(type: .init(.activeEnergyBurned), unit: .kilocalorie(), days: days)
            async let ex  = hk.fetchDailySumHistory(type: .init(.appleExerciseTime), unit: .minute(), days: days)
            async let st  = hk.fetchDailySumHistory(type: .init(.appleStandTime), unit: .second(), days: days)
            let (c, e, s) = await (cal, ex, st)
            let goal = max(moveGoalKcal, 100)
            return (0..<days).map { i in
                let mv = min((i < c.count ? c[i] : 0) / goal, 1)
                let eR = min((i < e.count ? e[i] : 0) / 30, 1)
                let sR = min((i < s.count ? s[i] / 3600 : 0) / 12, 1)
                return ((mv + eR + sR) / 3) * 100
            }
        case .strain:
            // Baseline-relative fallback strain per day (TRIMP needs per-day HR
            // sweeps — too many queries for a 60-day window).
            async let cal = hk.fetchDailySumHistory(type: .init(.activeEnergyBurned), unit: .kilocalorie(), days: days)
            async let stp = hk.fetchDailySumHistory(type: .init(.stepCount), unit: .count(), days: days)
            let (c, s) = await (cal, stp)
            let kcalBase = MetricBaseline.from(c)
            let stepsBase = MetricBaseline.from(s)
            return (0..<days).map { i in
                WellnessAlgorithms.strainScoreFallback(
                    activeKcal: i < c.count ? c[i] : 0,
                    steps: i < s.count ? s[i] : 0,
                    kcalBaseline: kcalBase,
                    stepsBaseline: stepsBase)
            }
        }
    }

    private func loadInsights() async -> [WellnessAlgorithms.Insight] {
        let hk = HealthKitService.shared
        async let hrvHist  = hk.fetchDailyAverageHistory(type: .init(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), days: 30)
        async let rhrHist  = hk.fetchDailyAverageHistory(type: .init(.restingHeartRate), unit: HKUnit(from: "count/min"), days: 30)
        async let sleepH   = hk.fetchDailySleepHistory(days: 30)
        async let stepsH   = hk.fetchDailySumHistory(type: .init(.stepCount), unit: .count(), days: 14)
        async let kcalH    = hk.fetchDailySumHistory(type: .init(.activeEnergyBurned), unit: .kilocalorie(), days: 14)
        let (hrv, rhr, sleep, steps, kcal) = await (hrvHist, rhrHist, sleepH, stepsH, kcalH)

        return WellnessAlgorithms.insights(
            hrvToday: hrv.last ?? 0, hrvBaseline: .from(hrv.dropLast()),
            rhrToday: rhr.last ?? 0, rhrBaseline: .from(rhr.dropLast()),
            sleepMinutesLast: sleep.last ?? 0, sleepBaseline: .from(sleep.dropLast()),
            stepsThisWeekAvg: nonZeroAvg(Array(steps.suffix(7))),
            stepsLastWeekAvg: nonZeroAvg(Array(steps.prefix(7))),
            kcalThisWeekAvg: nonZeroAvg(Array(kcal.suffix(7))),
            kcalLastWeekAvg: nonZeroAvg(Array(kcal.prefix(7)))
        )
    }
}

// MARK: - Helpers

private func nonZeroAvg(_ arr: [Double]) -> Double {
    let nz = arr.filter { $0 > 0 }
    guard !nz.isEmpty else { return 0 }
    return nz.reduce(0, +) / Double(nz.count)
}

private extension MetricBaseline {
    static func from(_ history: ArraySlice<Double>) -> MetricBaseline {
        .from(Array(history))
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    NavigationStack { ProgressAnalyticsView() }
}
