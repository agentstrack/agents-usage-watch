import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let snap: Snapshot?
    let config: ConfigIntent
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in: Context) -> Entry { Entry(date: .now, snap: nil, config: ConfigIntent()) }
    func snapshot(for config: ConfigIntent, in context: Context) async -> Entry {
        Entry(date: .now, snap: Snapshot.load() ?? (context.isPreview ? .sample : nil), config: config)
    }
    // One entry per minute so countdowns tick. New data arrives sooner: the menu bar app reloads the timeline
    // when a value changes; the 30-min policy is only the fallback (reload budget ~40-70/day).
    func timeline(for config: ConfigIntent, in: Context) async -> Timeline<Entry> {
        let snap = Snapshot.load(), now = Date.now
        let entries = (0..<30).map { Entry(date: now + Double($0) * 60, snap: snap, config: config) }
        return Timeline(entries: entries, policy: .after(now + 30 * 60))
    }
}

// MARK: - Rows

/// Medium widget: one weekly bar per account; Max's 5h usage sits next to the weekly %.
struct CompactRow: View {
    let row: Row, now: Date, config: ConfigIntent
    var caption = true
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                AccountHeader(row: row)
                if let h5 = row.h5 {
                    Text("5h \(Int(h5.rounded()))%").font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Usage.tone(h5) == .ok ? .secondary : Usage.tone(h5).color)
                }
                Pct(value: row.d7)
            }
            HStack(spacing: 8) {
                UsageBar(pct: row.d7 ?? 0, pace: config.showPace ? row.weekElapsed(at: now) : nil)
                // Without the caption line, keep the weekly reset visible next to the bar
                if !caption, let r = row.d7Reset {
                    Text(Usage.countdown(to: r, from: now))
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            if caption && row.status != .ok {
                StatusNote(row: row)
            } else if caption {
                HStack(spacing: 4) {
                    if let r = row.d7Reset { Text("Week resets in \(Usage.countdown(to: r, from: now))") }
                    if config.showTrend, let t = row.trendPerDay {
                        Text("·"); Text(String(format: "%+.1f%%/day", t))
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilitySummary(at: now))
    }
}

// MARK: - Families

struct UsageView: View {
    let e: Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let s = e.snap {
            let rows = s.rows(only: e.config.accountIds).map { $0.applyingResets(at: e.date) }
            if rows.isEmpty {
                message("None of the chosen accounts are in the data.", icon: "person.crop.circle.badge.questionmark")
            } else {
                switch family {
                case .systemSmall: small(s, rows)
                case .systemLarge: large(s, rows)
                default: medium(s, rows)
                }
            }
        } else {
            message("No usage data yet. Open the AgentsUsageWatch menu bar app.", icon: "chart.bar.xaxis")
        }
    }

    private func small(_ s: Snapshot, _ rows: [Row]) -> some View {
        // The first of the shown accounts (pick one in the widget's settings)
        let row = rows[0]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(row.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                PlanChip(plan: row.plan)
            }
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 7)
                Circle().trim(from: 0, to: min(row.d7 ?? 0, 100) / 100)
                    .stroke(Usage.tone(row.d7 ?? 0).color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90)).widgetAccentable()
                VStack(spacing: 0) {
                    Pct(value: row.d7, size: 18)
                    Text("week").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let h5 = row.h5 {
                FiveHourLine(pct: h5, reset: nil, now: e.date)
            } else if let r = row.d7Reset {
                Text("Resets in \(Usage.countdown(to: r, from: e.date))")
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilitySummary(at: e.date))
    }

    // Three accounts with captions don't fit 155pt, so fall back to header + bar only.
    private func medium(_ s: Snapshot, _ rows: [Row]) -> some View {
        ViewThatFits(in: .vertical) {
            mediumStack(s, rows, captions: true)
            mediumStack(s, rows, captions: false)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func mediumStack(_ s: Snapshot, _ rows: [Row], captions: Bool) -> some View {
        // Spacers spread rows over the full height instead of bunching them at the top
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.prefix(3).enumerated()), id: \.element.id) { i, row in
                if i > 0 { Spacer(minLength: 6) }
                CompactRow(row: row, now: e.date, config: e.config, caption: captions)
            }
            if s.isStale(at: e.date) { Spacer(minLength: 6); updated(s) }
        }
    }

    // Up to 4 cards when they fit (Ultra cards are shorter), else 3.
    private func large(_ s: Snapshot, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage").font(.system(size: 15, weight: .bold)).tracking(-0.2)
                Spacer()
                updated(s)
                Button(intent: RefreshIntent()) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Refresh now")
            }
            ViewThatFits(in: .vertical) {
                cards(s, rows.prefix(4))
                cards(s, rows.prefix(3))
                cards(s, rows.prefix(3), compact: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func cards(_ s: Snapshot, _ rows: ArraySlice<Row>, compact: Bool = false) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            ForEach(rows) { DetailCard(row: $0, now: e.date, showPace: e.config.showPace, showTrend: e.config.showTrend, stretch: true, compact: compact) }
        }
    }

    /// "Updated 3 minutes ago"; orange with a warning when the app missed its planned refresh (not running?).
    private func updated(_ s: Snapshot) -> some View {
        let stale = s.isStale(at: e.date)
        return HStack(spacing: 3) {
            if stale { Image(systemName: "exclamationmark.triangle.fill") }
            Text(stale ? "App not running · " : "Updated ") + Text(s.updated, format: .relative(presentation: .named, unitsStyle: .abbreviated))
        }
        .font(.system(size: 9)).foregroundStyle(stale ? AnyShapeStyle(Tone.warn.color) : AnyShapeStyle(.secondary))
        .lineLimit(1).minimumScaleFactor(0.8)
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

struct Background: View {
    let style: BackgroundStyle
    var body: some View {
        switch style {
        case .standard: Rectangle().fill(.fill.tertiary)
        case .transparent: Color.clear
        case .tinted:
            LinearGradient(colors: [accent.opacity(0.28), accent.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(.fill.tertiary)
        }
    }
}

@main struct Widgets: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        ProgressWidget()
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AgentsUsageWatch", intent: ConfigIntent.self, provider: Provider()) { e in
            UsageView(e: e)
                .containerBackground(for: .widget) { Background(style: e.config.background) }
                .widgetURL(URL(string: "agentsusagewatch://refresh"))  // a tap anywhere refreshes via the app
        }
        .configurationDisplayName("AgentsUsageWatch")
        .description("Weekly and 5-hour plan limits per Claude Code account.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Progress widget

struct ProgressEntry: TimelineEntry {
    let date: Date
    let snap: Snapshot?
    let config: ProgressIntent
}

/// The chart only changes when the app has new data (it reloads the widget then), so one entry is enough.
struct ProgressProvider: AppIntentTimelineProvider {
    func placeholder(in: Context) -> ProgressEntry { ProgressEntry(date: .now, snap: .sample, config: ProgressIntent()) }
    func snapshot(for config: ProgressIntent, in context: Context) async -> ProgressEntry {
        ProgressEntry(date: .now, snap: Snapshot.load() ?? (context.isPreview ? .sample : nil), config: config)
    }
    func timeline(for config: ProgressIntent, in: Context) async -> Timeline<ProgressEntry> {
        Timeline(entries: [ProgressEntry(date: .now, snap: Snapshot.load(), config: config)], policy: .after(.now + 30 * 60))
    }
}

struct ProgressWidgetView: View {
    let e: ProgressEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let s = e.snap {
            let rows = s.rows(only: e.config.accountIds).map { $0.applyingResets(at: e.date) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(e.config.period == .week ? "This week" : "Last 4 weeks")
                        .font(.system(size: 13, weight: .bold)).tracking(-0.2)
                    Spacer(minLength: 4)
                    // Current weekly % per account, in the chart's colours
                    ForEach(Array(rows.prefix(family == .systemLarge ? 5 : 3).enumerated()), id: \.element.id) { i, row in
                        HStack(spacing: 3) {
                            Circle().fill(ProgressChart.palette[i % ProgressChart.palette.count]).frame(width: 6, height: 6)
                            Text(row.name).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                            Pct(value: row.d7, size: 10)
                        }
                    }
                }
                ProgressChart(rows: rows, series: s.series ?? [:], days: e.config.period.days, now: e.date,
                              compact: family == .systemSmall)
                if family == .systemLarge, rows.count == 1, let row = rows.first {
                    TrendLine(row: row, now: e.date).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No usage data yet. Open the AgentsUsageWatch menu bar app.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AgentsUsageWatchProgress", intent: ProgressIntent.self, provider: ProgressProvider()) { e in
            ProgressWidgetView(e: e)
                .containerBackground(for: .widget) { Background(style: e.config.background) }
                .widgetURL(URL(string: "agentsusagewatch://refresh"))
        }
        .configurationDisplayName("Usage Progress")
        .description("How your weekly usage grew this week or over the last 4 weeks.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
