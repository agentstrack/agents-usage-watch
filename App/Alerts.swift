import Foundation

// Pure notification rules and usage history maths. The app feeds in rows + history and posts what comes out.

struct Sample: Codable, Equatable {
    let t: Date
    let id: String
    let d7: Double
    let r: Date?   // weekly reset time; a different r means a new week, so deltas across it are ignored
}

struct AlertSettings: Equatable {
    var enabled = true
    var fiveHourThresholds: [Double] = [80, 95]
    var weeklyThresholds: [Double] = [80, 95]
    var runOut = true          // "may run out before reset"
    var forecast = true        // mid-week "on track to use only X%"
    var burnRate = true        // "burning much faster than usual"
    var quietFrom: Int? = 23   // hour of day, nil = no quiet hours
    var quietTo: Int? = 8
}

struct Alert: Equatable {
    let key: String    // dedupe key; an alert with a sent key never repeats
    let title: String
    let body: String
}

enum Alerts {
    /// An account's weekly % since `since`, one point per `bucket` (its last sample), ending at the current value.
    /// Keeps the snapshot small: 28 days at 2 h is at most 337 points per account.
    static func series(_ history: [Sample], id: String, current: Double?, since: Date, now: Date,
                       bucket: TimeInterval = 7200) -> [Point] {
        var last: [Int: Sample] = [:]
        for s in history where s.id == id && s.t >= since && s.t <= now {
            last[Int(s.t.timeIntervalSince1970 / bucket)] = s
        }
        var points = last.keys.sorted().compactMap { last[$0].map { Point(t: $0.t, v: $0.d7) } }
        if let current, points.last?.t != now { points.append(Point(t: now, v: current)) }
        return points
    }

    static func inQuietHours(_ now: Date, _ s: AlertSettings, calendar: Calendar = .current) -> Bool {
        guard let from = s.quietFrom, let to = s.quietTo, from != to else { return false }
        let h = calendar.component(.hour, from: now)
        return from < to ? (h >= from && h < to) : (h >= from || h < to)
    }

    /// Alerts to post now. Quiet hours return nothing without marking anything sent, so a condition that
    /// still holds afterwards is reported then.
    static func evaluate(rows: [Row], history: [Sample], settings s: AlertSettings, sent: Set<String>,
                         now: Date) -> [Alert] {
        guard s.enabled, !inQuietHours(now, s) else { return [] }
        var out: [Alert] = []
        func add(_ a: Alert) { if !sent.contains(a.key) && !out.contains(where: { $0.key == a.key }) { out.append(a) } }

        for row in rows where row.status == .ok {
            // Thresholds: only the highest crossed one per window; lower ones are implied
            func threshold(_ label: String, _ pct: Double?, _ reset: Date?, _ levels: [Double]) {
                guard let pct, let level = levels.sorted(by: >).first(where: { pct >= $0 }) else { return }
                let window = reset.map { String(Int($0.timeIntervalSince1970)) } ?? "?"
                let when = reset.map { " · resets in \(Usage.countdown(to: $0, from: now))" } ?? ""
                add(Alert(key: "\(row.id)|\(label)|\(window)|\(Int(level))",
                          title: "\(row.name): \(label) usage at \(Int(pct.rounded()))%",
                          body: "Crossed \(Int(level))%\(when)."))
            }
            threshold("5-hour", row.h5, row.h5Reset, s.fiveHourThresholds)
            threshold("weekly", row.d7, row.d7Reset, s.weeklyThresholds)

            let window = row.d7Reset.map { String(Int($0.timeIntervalSince1970)) } ?? "?"
            if let p = row.projectedWeekly(at: now), let elapsed = row.weekElapsed(at: now), let reset = row.d7Reset {
                if s.runOut, p >= 100, elapsed >= 0.15, (row.d7 ?? 0) < 100 {
                    add(Alert(key: "\(row.id)|runout|\(window)",
                              title: "\(row.name) may run out before reset",
                              body: "On track for \(Int(p.rounded()))% of the week · resets in \(Usage.countdown(to: reset, from: now))."))
                }
                if s.forecast, elapsed >= 0.5, p < 60 {
                    add(Alert(key: "\(row.id)|forecast|\(window)",
                              title: "\(row.name): on track to use only \(Int(p.rounded()))% this week",
                              body: "About \(100 - Int(p.rounded()))% would go unused · resets in \(Usage.countdown(to: reset, from: now))."))
                }
            }
            if s.burnRate, let spike = burnSpike(history.filter { $0.id == row.id }, now: now) {
                // One per 3-hour bucket so a long busy stretch doesn't nag
                add(Alert(key: "\(row.id)|burn|\(Int(now.timeIntervalSince1970 / 10800))",
                          title: "\(row.name) is burning usage fast",
                          body: String(format: "+%.1f%% of the week in the last hour, about %.0f× your usual active hour.",
                                       spike.lastHour, spike.ratio)))
            }
        }
        return out
    }

    /// Weekly % added per clock hour, from consecutive samples within the same week.
    static func hourlyGains(_ samples: [Sample]) -> [Int: Double] {
        var gains: [Int: Double] = [:]
        let s = samples.sorted { $0.t < $1.t }
        for (a, b) in zip(s, s.dropFirst()) where a.r == b.r && b.d7 > a.d7 {
            gains[Int(b.t.timeIntervalSince1970 / 3600), default: 0] += b.d7 - a.d7
        }
        return gains
    }

    /// Last 60 min vs the median of active hours (hours with any usage) over the past 7 days.
    /// Needs 12+ active hours of baseline; fires at 3× the median and at least +2% of the week.
    static func burnSpike(_ samples: [Sample], now: Date) -> (lastHour: Double, ratio: Double)? {
        let s = samples.sorted { $0.t < $1.t }
        var lastHour = 0.0
        for (a, b) in zip(s, s.dropFirst()) where a.r == b.r && b.d7 > a.d7 && b.t > now - 3600 && b.t <= now {
            lastHour += b.d7 - a.d7
        }
        let cutoff = Int((now - 3600).timeIntervalSince1970 / 3600), weekAgo = Int((now - 7 * 86400).timeIntervalSince1970 / 3600)
        let baseline = hourlyGains(s).filter { $0.key < cutoff && $0.key >= weekAgo && $0.value > 0 }.map(\.value).sorted()
        guard baseline.count >= 12 else { return nil }
        let median = baseline[baseline.count / 2]
        guard lastHour >= 2, lastHour >= 3 * median else { return nil }
        return (lastHour, lastHour / median)
    }

    /// Weekly % added since local midnight, from the history (nil without a sample from before today).
    static func today(_ samples: [Sample], current: Double?, reset: Date?, now: Date, calendar: Calendar = .current) -> Double? {
        guard let current else { return nil }
        let midnight = calendar.startOfDay(for: now)
        guard let base = samples.filter({ $0.t <= midnight }).max(by: { $0.t < $1.t }) else { return nil }
        return base.r == reset ? current - base.d7 : current  // a reset since midnight: all of it is today's
    }
}
