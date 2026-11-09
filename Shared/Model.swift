import Foundation

// usage.json in the app group: written by the menu bar app, read by the widget.
// Optional fields are nil when an account has no such window (Ultra has no 5h limit since Oct 2026)
// or its usage has never been read.
struct Row: Codable, Identifiable, Equatable {
    let id: String            // stable: the account's config folder path
    let name: String          // display name, e.g. "WORK"
    let plan: String          // "ultra", "max", "pro", or the raw tier
    let h5: Double?           // % used
    let h5Reset: Date?
    let d7: Double?
    let d7Reset: Date?
    let trendPerDay: Double?  // avg weekly % added per day this week
    let today: Double?        // weekly % added today
    let status: Status
    let fetchedAt: Date?      // last successful read; values are "as of" this when status isn't .ok
    var spend: Spend? = nil   // agents that report usage, not a limit (opencode): shown instead of the bars

    enum Status: String, Codable {
        case ok, expired, notLoggedIn, rateLimited, apiChanged, offline, error
        case notConnected  // status line helper not set up for this account
        case waiting       // set up, but Claude Code hasn't sent a message since
        case idle          // values from the last Claude Code use, a while ago

        /// Unknown values (from a newer app version) read as an error instead of failing the whole snapshot.
        init(from decoder: Decoder) throws {
            self = Status(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .error
        }

        var label: String? {
            switch self {
            case .ok: nil
            case .expired: "Login expired"
            case .notLoggedIn: "Not logged in"
            case .rateLimited: "Rate limited"
            case .apiChanged: "Format changed"
            case .offline: "Offline"
            case .error: "Couldn't update"
            case .notConnected: "Set up in Settings"
            case .waiting: "Waiting for first message"
            case .idle: "Last used"
            }
        }
    }

    var hasFiveHourLimit: Bool { h5 != nil }
    var isLimitReached: Bool { (h5 ?? 0) >= 100 || (d7 ?? 0) >= 100 }

    /// Fraction of the 7-day window already elapsed (0...1), from its reset time.
    /// nil once the reset has passed and we haven't read the new window yet: there's no pace to show.
    func weekElapsed(at now: Date) -> Double? {
        guard let d7Reset, d7Reset > now else { return nil }
        return min(max(1 - d7Reset.timeIntervalSince(now) / Usage.week, 0), 1)
    }

    /// Weekly % used by reset if the rest of the week goes at this week's average rate.
    /// nil in the first ~8h of a week, when one session would swing it wildly.
    func projectedWeekly(at now: Date) -> Double? {
        guard let d7, let elapsed = weekElapsed(at: now), elapsed >= 0.05 else { return nil }
        return d7 / elapsed
    }

    /// A window whose reset time has passed is empty again, even if we couldn't re-read it.
    func applyingResets(at now: Date) -> Row {
        func reset(_ v: Double?, _ at: Date?) -> Double? { (at.map { $0 <= now } ?? false) ? 0 : v }
        return Row(id: id, name: name, plan: plan, h5: reset(h5, h5Reset), h5Reset: h5Reset,
                   d7: reset(d7, d7Reset), d7Reset: d7Reset, trendPerDay: trendPerDay, today: today,
                   status: status, fetchedAt: fetchedAt, spend: spend)
    }

    /// One VoiceOver sentence per account, e.g. "Work, Max. Week 9 percent used, resets in 4d 11h. 5-hour 5 percent."
    func accessibilitySummary(at now: Date) -> String {
        var parts = ["\(name.capitalized), \(Usage.planLabel(plan))\(status.label.map { ", \($0)" } ?? "")"]
        if let d7 { parts.append("Week \(Int(d7.rounded())) percent used" + (d7Reset.map { ", resets in \(Usage.countdown(to: $0, from: now))" } ?? "")) }
        if let h5 { parts.append("5-hour \(Int(h5.rounded())) percent") }
        if let spend { parts.append("Today \(Spend.tokens(spend.tokensToday)) tokens, \(Spend.cost(spend.costToday)). Last 7 days \(Spend.cost(spend.costWeek))") }
        return parts.joined(separator: ". ")
    }
}

/// Tokens and cost for agents with no plan window (pay-as-you-go): today and the last 7 days.
struct Spend: Codable, Equatable {
    var tokensToday = 0, tokensWeek = 0
    var costToday = 0.0, costWeek = 0.0

    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? String(format: "%.1fk", Double(n) / 1e3) : "\(n)"
    }
    static func cost(_ c: Double) -> String { c > 0 && c < 0.01 ? "<$0.01" : String(format: "$%.2f", c) }
}

/// One point of an account's weekly-% history, for the progress chart.
struct Point: Codable, Equatable {
    let t: Date
    let v: Double
}

struct Snapshot: Codable {
    var schemaVersion = 1
    let updated: Date
    let nextUpdate: Date      // when the app plans its next refresh; the widget uses it to spot a dead app
    let rows: [Row]
    /// Weekly % over the last 28 days by account id, one point per 2 h (the widget can't read the history file).
    var series: [String: [Point]]? = nil

    /// From the AppGroup Info.plist key (set from APP_GROUP_ID in Config/Base.xcconfig), so forks build as-is.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? ""
    static let file = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
        .appendingPathComponent("usage.json")

    static func load() -> Snapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder.usage.decode(Snapshot.self, from: data)
    }

    /// No refresh for 10 min past the planned one: the app isn't running or the Mac was asleep.
    func isStale(at now: Date) -> Bool { now.timeIntervalSince(nextUpdate) > 10 * 60 }

    /// Rows to show: the chosen accounts in data order, or all of them when none are chosen.
    func rows(only ids: [String]) -> [Row] {
        ids.isEmpty ? rows : rows.filter { ids.contains($0.id) }
    }

    /// Shown in the widget gallery before the app has ever run.
    static let sample = Snapshot(updated: .now, nextUpdate: .now + 300, rows: [
        Row(id: "/sample/a", name: "WORK", plan: "ultra", h5: nil, h5Reset: nil, d7: 24, d7Reset: .now + 4 * 86400,
            trendPerDay: 8, today: 3, status: .ok, fetchedAt: .now),
        Row(id: "/sample/b", name: "PERSONAL", plan: "max", h5: 35, h5Reset: .now + 7200, d7: 62,
            d7Reset: .now + 2 * 86400, trendPerDay: 12, today: 9, status: .ok, fetchedAt: .now),
    ], series: [
        "/sample/a": (0...36).map { Point(t: .now - Double(36 - $0) * 7200, v: Double($0) * 0.66) },
        "/sample/b": (0...60).map { Point(t: .now - Double(60 - $0) * 7200, v: Double($0)) },
    ])
}

extension JSONDecoder {
    static var usage: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

extension JSONEncoder {
    static var usage: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

/// Darwin notification the widget's refresh button posts and the app listens for.
enum RefreshSignal {
    static let name = "agentsusagewatch.refresh"
}

enum Tone { case ok, warn, critical }

enum Usage {
    static let week: TimeInterval = 7 * 86400

    static func tone(_ pct: Double) -> Tone { pct >= 85 ? .critical : pct >= 60 ? .warn : .ok }

    /// "4d 3h", "2h 05m", "12m", "now".
    static func countdown(to date: Date, from now: Date) -> String {
        let s = Int(date.timeIntervalSince(now))
        guard s > 59 else { return "now" }
        let d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        return "\(m)m"
    }

    static func planLabel(_ plan: String) -> String {
        switch plan { case "ultra": "Ultra"; case "max": "Max"; case "pro": "Pro"; case "-", "": "?"; default: plan }
    }
}
