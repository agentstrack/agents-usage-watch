import Charts
import SwiftUI
import WidgetKit

// Views shared by the widget and the menu bar panel.

// AgentsTrack indigo for the Ultra chip, the tinted widget background and the first chart line.
let accent = Color(red: 0.39, green: 0.40, blue: 0.95)

extension Tone {
    var color: Color {
        switch self { case .ok: .green; case .warn: .orange; case .critical: .red }
    }
}

struct PlanChip: View {
    let plan: String
    var body: some View {
        let ultra = plan == "ultra"
        Text(Usage.planLabel(plan).uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.6)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .foregroundStyle(ultra ? accent : .secondary)
            .background(Capsule().fill(ultra ? accent.opacity(0.16) : Color.primary.opacity(0.08)))
    }
}

/// Usage bar; the optional tick marks where usage would be if spread evenly over the window.
struct UsageBar: View {
    let pct: Double
    var pace: Double? = nil
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1)).frame(height: height)
                Capsule()
                    .fill(Usage.tone(pct).color.gradient)
                    .frame(width: max(height, g.size.width * min(pct, 100) / 100), height: height)
                    .opacity(pct > 0 ? 1 : 0)
                    .widgetAccentable()
                if let pace {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: height + 4)
                        .offset(x: min(max(g.size.width * pace - 1, 0), g.size.width - 2))
                }
            }
        }
        .frame(height: height + 4)
    }
}

/// Percentage; in vibrant/accented rendering (colours flattened) warn/critical get a symbol instead.
struct Pct: View {
    let value: Double?
    var size: CGFloat = 13
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        HStack(spacing: 2) {
            if mode != .fullColor, let value, Usage.tone(value) != .ok {
                Image(systemName: Usage.tone(value) == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: size * 0.7))
            }
            Text(value.map { "\(Int($0.rounded()))%" } ?? "–")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

struct AccountHeader: View {
    let row: Row
    var body: some View {
        HStack(spacing: 5) {
            Text(row.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            PlanChip(plan: row.plan)
            if row.isLimitReached {
                Text("LIMIT REACHED").font(.system(size: 8, weight: .bold)).tracking(0.6).foregroundStyle(.red)
            }
            Spacer(minLength: 4)
        }
    }
}

/// "Login expired · as of 14:20" when the account couldn't be updated; values shown are the last good ones.
struct StatusNote: View {
    let row: Row
    var body: some View {
        if let label = row.status.label {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.circle.fill")
                Text(label + (row.fetchedAt.map { " · as of \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
            }
            .font(.system(size: 10)).foregroundStyle(Tone.warn.color).lineLimit(1)
        }
    }
}

/// "+3.8%/day · on track for 52%". The projection turns orange/red when the week would run out.
struct TrendLine: View {
    let row: Row
    let now: Date
    var body: some View {
        HStack(spacing: 4) {
            if let t = row.trendPerDay { Text(String(format: "%+.1f%%/day", t)) }
            if let p = row.projectedWeekly(at: now) {
                Text("·")
                Text(p >= 100 ? "runs out before reset" : "on track for \(Int(p.rounded()))%")
                    .foregroundStyle(p >= 100 ? Tone.critical.color : p >= 85 ? Tone.warn.color : .secondary)
            }
        }
        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
    }
}

/// "5h ▬▬▭▭ 7% · 4h 33m": the 5-hour window, for plans that have one (Ultra doesn't).
struct FiveHourLine: View {
    let pct: Double, reset: Date?, now: Date
    var body: some View {
        HStack(spacing: 6) {
            Text("5h").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            UsageBar(pct: pct, height: 4)
            Pct(value: pct, size: 10)
            if let reset {
                Text(Usage.countdown(to: reset, from: now))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

/// One account as a card: weekly % as the hero number, weekly bar with pace marker, reset + trend or
/// status, and a slim 5-hour bar when the plan has one.
struct DetailCard: View {
    let row: Row, now: Date
    var showPace = true, showTrend = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                AccountHeader(row: row)
                Pct(value: row.d7, size: 20)
            }
            UsageBar(pct: row.d7 ?? 0, pace: showPace ? row.weekElapsed(at: now) : nil, height: 8)
            HStack(spacing: 4) {
                if row.status != .ok { StatusNote(row: row) }
                else if let r = row.d7Reset { Text("Resets in \(Usage.countdown(to: r, from: now))") }
                Spacer(minLength: 6)
                if showTrend && row.status == .ok { TrendLine(row: row, now: now) }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            if let h5 = row.h5 { FiveHourLine(pct: h5, reset: row.h5Reset, now: now) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilitySummary(at: now))
    }
}

// MARK: - Progress chart

/// Weekly % over time, one line per account. With a single account over one week it shows that account's own
/// week (start to reset) with a dashed even-pace line, so above the line means ahead of pace.
struct ProgressChart: View {
    let rows: [Row]
    let series: [String: [Point]]
    let days: Int            // 7 or 28
    let now: Date
    var compact = false

    static let palette: [Color] = [accent, .teal, .orange, .pink, .green]

    private var single: Row? { rows.count == 1 && days == 7 ? rows.first : nil }

    private var domain: ClosedRange<Date> {
        if let r = single?.d7Reset, r > now { return (r - Usage.week)...r }
        return (now - Double(days) * 86400)...now
    }

    var body: some View {
        let names = rows.map(\.name)
        Chart {
            ForEach(rows) { row in
                ForEach(points(row), id: \.t) { p in
                    LineMark(x: .value("Time", p.t), y: .value("Weekly %", p.v), series: .value("Account", row.name))
                        .foregroundStyle(by: .value("Account", row.name))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: compact ? 1.5 : 2))
                }
            }
            if let r = single?.d7Reset, r > now {
                LineMark(x: .value("Time", r - Usage.week), y: .value("Weekly %", 0), series: .value("Account", "pace"))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                LineMark(x: .value("Time", r), y: .value("Weekly %", 100), series: .value("Account", "pace"))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(domain: names, range: Array(Self.palette.prefix(max(names.count, 1))))
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { v in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                if !compact { AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 8)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days > 7 ? 7 : 1)) { _ in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.05))
                if !compact { AxisValueLabel(format: days > 7 ? .dateTime.day().month(.abbreviated) : .dateTime.weekday(.narrow)).font(.system(size: 8)) }
            }
        }
        .chartLegend(rows.count > 1 && !compact ? .visible : .hidden)
        .accessibilityLabel("Weekly usage over the last \(days) days")
    }

    private func points(_ row: Row) -> [Point] {
        (series[row.id] ?? []).filter { domain.contains($0.t) }
    }
}
