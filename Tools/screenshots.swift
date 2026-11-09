// Renders the README/website screenshots offscreen from the app's own SwiftUI views with invented sample data
// (never the real app or real accounts). Writes docs/images/*.png.
// Usage (from the repo root):
//   swiftc -O -parse-as-library Tools/screenshots.swift Shared/Model.swift Shared/Views.swift -o build/screenshots && build/screenshots docs/images \
//     && pngquant --force --skip-if-larger --ext .png --quality 85-98 docs/images/*.png   # optional, shrinks ~3x
// The menu panel and widget layouts are copies of App/MenuView.swift and Widget/UsageWidget.swift (those need
// Store / AppIntents); keep them in step when the real layouts change.
import AppKit
import Charts
import SwiftUI

// MARK: - Sample data

private let cal = Calendar(identifier: .gregorian)
/// Fixed "now" so the output is reproducible: a Thursday afternoon.
private let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14, minute: 40))!
private let h: TimeInterval = 3600, d: TimeInterval = 86400

private func row(_ id: String, _ plan: String, d7: Double?, d7Reset: TimeInterval?, h5: Double? = nil,
                 h5Reset: TimeInterval? = nil, trend: Double? = nil, today: Double? = nil, spend: Spend? = nil) -> Row {
    Row(id: id, name: id, plan: plan, h5: h5, h5Reset: h5Reset.map { now + $0 }, d7: d7,
        d7Reset: d7Reset.map { now + $0 }, trendPerDay: trend, today: today, status: .ok, fetchedAt: now, spend: spend)
}

private let rows: [Row] = [
    row("WORK", "ultra", d7: 42, d7Reset: 3 * d + 4 * h, trend: 6.1, today: 5),
    row("PERSONAL", "max", d7: 68, d7Reset: 1 * d + 20 * h, h5: 35, h5Reset: 2 * h + 10 * 60, trend: 13.2, today: 11),
    row("CODEX", "plus", d7: 23, d7Reset: 4 * d + 6 * h, h5: 12, h5Reset: 3 * h + 25 * 60, trend: 8.4, today: 4),
    row("ANTIGRAVITY", "pro", d7: 9, d7Reset: 5 * d + 10 * h, h5: 4, h5Reset: 4 * h + 5 * 60, trend: 5.7, today: 2),
    row("OPENCODE", "-", d7: nil, d7Reset: nil,
        spend: Spend(tokensToday: 2_300_000, tokensWeek: 11_600_000, costToday: 1.84, costWeek: 9.40)),
]

/// Deterministic weekly-% history, one point per 2 h: daytime-heavy activity that climbs through each week to
/// `ends` (newest past week first) and drops to 0 at every reset; the current week lands on the row's d7 now.
private func history(_ r: Row, ends: [Double], seed: UInt64) -> [Point] {
    var s = seed
    func rand() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    let reset = r.d7Reset!, slot = 2 * h
    var out: [Point] = []
    for k in (0...4).reversed() {   // 4 = oldest, 0 = current week
        let start = reset - Usage.week * Double(k + 1)
        let acts = (0..<84).map { i -> Double in
            let t = start + Double(i) * slot
            let hour = cal.component(.hour, from: t), wd = cal.component(.weekday, from: t)
            let day = (9...21).contains(hour) ? 1.0 : 0.06, weekend = (wd == 1 || wd == 7) ? 0.35 : 1
            return rand() < 0.15 ? 0 : day * weekend * (0.3 + 1.4 * rand())
        }
        let last = k == 0 ? Int(now.timeIntervalSince(start) / slot) : 83
        let target = k == 0 ? r.d7! : ends[min(k - 1, ends.count - 1)]
        let total = max(acts[0...last].reduce(0, +), 0.001)
        var cum = 0.0
        for i in 0...last {
            cum += acts[i]
            let t = start + Double(i) * slot
            if t >= now - 29 * d { out.append(Point(t: t, v: cum / total * target)) }
        }
        if k == 0 { out.append(Point(t: now, v: r.d7!)) }
    }
    return out
}

private let series: [String: [Point]] = [
    "WORK": history(rows[0], ends: [71, 64, 80, 58], seed: 11),
    "PERSONAL": history(rows[1], ends: [88, 95, 74, 81], seed: 23),
    "CODEX": history(rows[2], ends: [46, 39, 52, 30], seed: 37),
    "ANTIGRAVITY": history(rows[3], ends: [18, 25, 12, 20], seed: 41),
]

// MARK: - Menu panel (App/MenuView.swift, with Store replaced by the sample rows)

/// Stand-in for the small segmented Picker: AppKit-backed controls don't draw in ImageRenderer.
private struct FakeSegmented: View {
    let items: [String], selected: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Text(items[i]).font(.system(size: 11))
                    .padding(.horizontal, 9).frame(height: 18)
                    .background {
                        if i == selected {
                            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                .fill(scheme == .dark ? Color(white: 0.42) : .white)
                                .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
                        }
                    }
            }
        }
        .padding(1)
        .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}

private struct Panel: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage").font(.system(size: 15, weight: .bold)).tracking(-0.2)
                Spacer()
                Text("Updated just now").font(.system(size: 10)).foregroundStyle(.secondary)
                Image(systemName: "arrow.clockwise").foregroundStyle(.secondary).frame(width: 18)
            }
            VStack(spacing: 8) {
                ForEach(rows) { DetailCard(row: $0, now: now, compact: rows.count > 4) }
            }
            let charted = rows.filter { $0.spend == nil }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Progress").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    FakeSegmented(items: ["Week", "4 weeks"], selected: 0)
                }
                ProgressChart(rows: charted, series: series, days: 7, now: now).frame(height: 110)
                ChartLegend(rows: charted)
            }
            Divider()
            HStack { Text("Settings…"); Spacer(); Text("Quit") }.font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(scheme == .dark ? Color(white: 0.16) : Color(white: 0.955))
            .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.18 : 0.12), lineWidth: 0.5))
    }
}

// MARK: - Widgets (Widget/UsageWidget.swift; config at its defaults: pace + trend on, standard background)

private enum Family { case small, medium, large
    var size: CGSize { switch self { case .small: CGSize(width: 170, height: 170)
                                     case .medium: CGSize(width: 364, height: 170)
                                     case .large: CGSize(width: 364, height: 382) } }
}

private struct WidgetFrame<Content: View>: View {
    let family: Family
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        content
            .padding(16)
            .frame(width: family.size.width, height: family.size.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(scheme == .dark ? Color(red: 0.118, green: 0.118, blue: 0.118) : Color(white: 0.95)))
    }
}

/// CompactRow from UsageWidget.swift with ConfigIntent replaced by its defaults.
private struct CompactRow: View {
    let row: Row
    var caption = true
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                AccountHeader(row: row)
                if let h5 = row.h5 {
                    Text("5h \(Int(h5.rounded()))%").font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Usage.tone(h5) == .ok ? .secondary : Usage.tone(h5).color)
                }
                if let spend = row.spend { SpendHero(spend: spend, size: 13) } else { Pct(value: row.d7) }
            }
            if let spend = row.spend {
                if caption { SpendLine(spend: spend) }
            } else {
                HStack(spacing: 8) {
                    UsageBar(pct: row.d7 ?? 0, pace: row.weekElapsed(at: now))
                    if !caption, let r = row.d7Reset {
                        Text(Usage.countdown(to: r, from: now))
                            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                if caption {
                    HStack(spacing: 4) {
                        if let r = row.d7Reset { Text("Week resets in \(Usage.countdown(to: r, from: now))") }
                        if let t = row.trendPerDay { Text("·"); Text(String(format: "%+.1f%%/day", t)) }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

private func list(_ rows: [Row], captions: Bool, limit: Int? = nil) -> some View {
    let shown = rows.prefix(limit ?? rows.count)
    return VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
            if i > 0 { Spacer(minLength: 6) }
            CompactRow(row: row, caption: captions)
        }
        if rows.count > shown.count {
            Spacer(minLength: 6)
            Text("+\(rows.count - shown.count) more · right-click › Edit Widget to choose")
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// AccountSwitcher's label (the real one is an AppIntent button).
private func switcher(_ row: Row, count: Int, @ViewBuilder accessory: () -> some View) -> some View {
    HStack(spacing: 4) {
        Text(row.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        if count > 1 { Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
        Spacer(minLength: 2)
        accessory()
    }
}

private struct SmallWidget: View {
    let row: Row, count: Int
    var body: some View {
        WidgetFrame(family: .small) {
            VStack(alignment: .leading, spacing: 6) {
                switcher(row, count: count) { PlanChip(plan: row.plan) }
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 7)
                    Circle().trim(from: 0, to: min(row.d7 ?? 0, 100) / 100)
                        .stroke(Usage.tone(row.d7 ?? 0).color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Pct(value: row.d7, size: 18)
                        Text("week").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let h5 = row.h5 {
                    FiveHourLine(pct: h5, reset: nil, now: now)
                } else if let r = row.d7Reset {
                    Text("Resets in \(Usage.countdown(to: r, from: now))")
                        .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct MediumWidget: View {
    let rows: [Row]
    var body: some View {
        WidgetFrame(family: .medium) {
            ViewThatFits(in: .vertical) {
                list(rows, captions: true)
                list(rows, captions: false)
                list(rows, captions: false, limit: 3)
                list(rows, captions: false, limit: 2)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct LargeWidget: View {
    let rows: [Row]
    var body: some View {
        WidgetFrame(family: .large) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Usage").font(.system(size: 15, weight: .bold)).tracking(-0.2)
                    Spacer()
                    Text("Updated 1 min. ago").font(.system(size: 9)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .vertical) {
                    if rows.count <= 4 {
                        cards(rows)
                        cards(rows, compact: true)
                    }
                    list(rows, captions: true)
                    list(rows, captions: false)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func cards(_ rows: [Row], compact: Bool = false) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            ForEach(rows) { DetailCard(row: $0, now: now, stretch: true, compact: compact) }
        }
    }
}

private struct ProgressLargeWidget: View {
    let rows: [Row]
    var body: some View {
        WidgetFrame(family: .large) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This week").font(.system(size: 13, weight: .bold)).tracking(-0.2)
                ProgressChart(rows: rows, series: series, days: 7, now: now)
                ChartLegend(rows: rows, showPct: true)
            }
        }
    }
}

// MARK: - Hero

private struct Hero: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.10, blue: 0.20), Color(red: 0.05, green: 0.05, blue: 0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.31, green: 0.27, blue: 0.90).opacity(0.38), .clear],
                           center: UnitPoint(x: 0.3, y: 0.15), startRadius: 0, endRadius: 640)
            RadialGradient(colors: [Color.teal.opacity(0.16), .clear],
                           center: UnitPoint(x: 0.85, y: 0.9), startRadius: 0, endRadius: 520)
            HStack(alignment: .center, spacing: 48) {
                Panel().fixedSize().shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                VStack(alignment: .leading, spacing: 24) {
                    LargeWidget(rows: Array(rows.prefix(2)) + [rows[2], rows[4]])
                    HStack(spacing: 24) {
                        SmallWidget(row: rows[1], count: rows.count)
                        SmallWidget(row: rows[0], count: rows.count)
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            }
        }
    }
}

// MARK: - Render

@MainActor
private func render(_ view: some View, dark: Bool = true, scale: CGFloat = 2, to url: URL) {
    let content = view
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.locale, Locale(identifier: "en_US"))
    // accent and system colours are dynamic NSColors: resolve them in the matching appearance too
    NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
        let r = ImageRenderer(content: content)
        r.scale = scale
        r.isOpaque = false
        guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            fatalError("render failed: \(url.lastPathComponent)")
        }
        try! png.write(to: url)
        print("\(url.lastPathComponent)  \(cg.width)x\(cg.height)")
    }
}

@main struct Screenshots {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/images")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let charted = rows.filter { $0.spend == nil }
        render(Panel().padding(12), dark: true, to: dir.appendingPathComponent("panel-dark.png"))
        render(Panel().padding(12), dark: false, to: dir.appendingPathComponent("panel-light.png"))
        // Widgets as a user would configure them: large with four accounts (cards), medium with three
        render(LargeWidget(rows: [rows[0], rows[1], rows[2], rows[4]]), to: dir.appendingPathComponent("widget-large.png"))
        render(MediumWidget(rows: Array(rows.prefix(3))), to: dir.appendingPathComponent("widget-medium.png"))
        render(SmallWidget(row: rows[1], count: rows.count), to: dir.appendingPathComponent("widget-small.png"))
        render(ProgressLargeWidget(rows: charted), to: dir.appendingPathComponent("widget-progress.png"))
        // 1600x1000 px: a 1240x775 pt canvas, tall enough for the whole panel
        render(Hero().frame(width: 1240, height: 775), scale: 1600 / 1240, to: dir.appendingPathComponent("hero.png"))
    }
}
