import AppKit
import Foundation
import OSLog
import UserNotifications

/// `log stream --predicate 'subsystem == "<bundle id>"'` to watch it work. Never logs tokens.
let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "agentsusagewatch", category: "app")
import WidgetKit

/// App state: accounts, latest rows, refresh loop, history, alerts and the widget snapshot.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var accounts: [Account] = [] { didSet { save(accounts, "accounts") } }
    @Published private(set) var rows: [String: Row] = [:]     // by account id, hidden ones included
    @Published private(set) var refreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var nextRefresh: Date?
    @Published private(set) var series: [String: [Point]] = [:]   // what the progress charts draw

    private let defaults = UserDefaults.standard
    private var history: [Sample] = []
    private var timer: Timer?
    private var backoff: [String: (until: Date, delay: TimeInterval)] = [:]
    private var lastWidgetReload = Date.distantPast
    private var lastWidgetKey = ""
    private var forceWidgetReload = false

    // MARK: Settings (UserDefaults keys shared with SettingsView's @AppStorage)

    static let intervals: [Int] = [30, 60, 120, 300, 600, 900]
    var interval: TimeInterval { TimeInterval(defaults.object(forKey: "refreshInterval") as? Int ?? 300) }
#if TESTING
    var wakeExpired: Bool { defaults.object(forKey: "wakeExpired") as? Bool ?? true }
#endif
    var alertSettings: AlertSettings {
        var s = AlertSettings()
        s.enabled = defaults.object(forKey: "alertsEnabled") as? Bool ?? true
        s.fiveHourThresholds = [defaults.object(forKey: "fiveHourWarn") as? Double ?? 80, defaults.object(forKey: "fiveHourCritical") as? Double ?? 95]
        s.weeklyThresholds = [defaults.object(forKey: "weeklyWarn") as? Double ?? 80, defaults.object(forKey: "weeklyCritical") as? Double ?? 95]
        s.runOut = defaults.object(forKey: "alertRunOut") as? Bool ?? true
        s.forecast = defaults.object(forKey: "alertForecast") as? Bool ?? true
        s.burnRate = defaults.object(forKey: "alertBurnRate") as? Bool ?? true
        let quiet = defaults.object(forKey: "quietHours") as? Bool ?? true
        s.quietFrom = quiet ? defaults.object(forKey: "quietFrom") as? Int ?? 23 : nil
        s.quietTo = quiet ? defaults.object(forKey: "quietTo") as? Int ?? 8 : nil
        return s
    }

    /// Visible accounts' rows in the user's order, with passed resets applied.
    var visibleRows: [Row] {
        accounts.filter { !$0.hidden }.compactMap { rows[$0.id]?.applyingResets(at: .now) }
    }

    // MARK: Lifecycle

    func start() {
        accounts = Accounts.merge(saved: load("accounts") ?? [], found: Accounts.discover())
        rows = Dictionary(uniqueKeysWithValues: (Snapshot.load()?.rows ?? []).map { ($0.id, $0) })  // last known values
        history = History.load()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
#if !TESTING
        if accounts.contains(where: { StatusLine.isConnected($0) }) { StatusLine.installHelper() }  // keep it current
#endif
        observeSystem()
        refreshNow()
    }

    func rescan() {
        accounts = Accounts.merge(saved: accounts, found: Accounts.discover())
        refreshNow()
    }

    func addAccount(folder: URL) {
        let a = Accounts.make(folder.path, manual: true)
        guard !accounts.contains(where: { $0.id == a.id }) else { return }
        accounts.append(a)
        refreshNow()
    }

    func removeAccount(_ id: String) {
        accounts.removeAll { $0.id == id && $0.manual }
        rows[id] = nil
        writeSnapshot(force: true)
    }

    /// Refreshes right away (rate-limit backoff still applies) and re-plans the timer, e.g. after an
    /// interval change. `byUser` (widget button, menu, settings) also reloads the widget straight away.
    func refreshNow(byUser: Bool = true) {
        log.info("refresh requested")
        if byUser { forceWidgetReload = true }
        Task { await refresh() }
    }

#if !TESTING
    /// Settings > Accounts "Set up": points this account's status line at our helper.
    func connect(_ account: Account) throws {
        try StatusLine.connect(account, all: accounts)
        refreshNow()
    }

    func disconnect(_ account: Account) throws {
        try StatusLine.disconnect(account, all: accounts)
        refreshNow()
    }
#endif

    private func schedule() {
        timer?.invalidate()
        nextRefresh = .now + interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in await Store.shared.refresh() }
        }
    }

    // MARK: Refresh

    func refresh() async {
        guard !refreshing else { log.info("refresh skipped: one is running"); return }
        log.info("refresh start")
        refreshing = true
        defer { refreshing = false; schedule() }

        let now = Date.now
        let due = accounts.filter { !$0.hidden && (backoff[$0.id]?.until ?? .distantPast) <= now }
#if TESTING
        let wake = wakeExpired
        let results = await withTaskGroup(of: (Account, FetchResult).self) { group in
            for a in due { group.addTask { (a, await Fetcher.fetch(a, wakeExpired: wake)) } }
            return await group.reduce(into: []) { $0.append($1) }
        }
#else
        let results = due.map { ($0, StatusLine.read($0, now: now)) }
#endif
        for (a, result) in results {
            if case let .failed(status, _, _) = result { log.notice("\(a.name, privacy: .public): \(status.rawValue, privacy: .public)") }
            apply(a, result, now: now)
        }
        log.info("refresh done: \(results.count) account(s)")
        lastRefresh = now
        nextRefresh = now + interval
        History.prune(&history, now: now)
        writeSnapshot()
        notify(now: now)
    }

    private func apply(_ a: Account, _ result: FetchResult, now: Date) {
        let old = rows[a.id]
        switch result {
        case let .ok(w, plan, at):
            backoff[a.id] = nil
            let elapsedDays = w.d7Reset.map { max(7 - $0.timeIntervalSince(now) / 86400, 1) }
            let mine = history.filter { $0.id == a.id }
            // Status line values are as old as the last Claude Code message; say so once that's a while ago
            let status: Row.Status = now.timeIntervalSince(at) > StatusLine.idleAfter ? .idle : .ok
            rows[a.id] = Row(id: a.id, name: a.name, plan: plan, h5: w.h5, h5Reset: w.h5Reset, d7: w.d7, d7Reset: w.d7Reset,
                             trendPerDay: w.d7.flatMap { d7 in elapsedDays.map { d7 / $0 } },
                             today: Alerts.today(mine, current: w.d7, reset: w.d7Reset, now: now),
                             status: status, fetchedAt: at)
            if let d7 = w.d7 { History.append(Sample(t: at, id: a.id, d7: d7, r: w.d7Reset), to: &history) }
        case let .failed(status, plan, retryAfter):
            if status == .rateLimited {
                // Honour Retry-After, else back off 60 s -> 15 min
                let delay = retryAfter ?? min((backoff[a.id]?.delay ?? 30) * 2, 900)
                backoff[a.id] = (now + delay, delay)
            }
            // Keep the last good values; only the status (and a fresher plan) changes
            rows[a.id] = Row(id: a.id, name: a.name, plan: plan ?? old?.plan ?? "-", h5: old?.h5, h5Reset: old?.h5Reset,
                             d7: old?.d7, d7Reset: old?.d7Reset, trendPerDay: old?.trendPerDay, today: old?.today,
                             status: status, fetchedAt: old?.fetchedAt)
        }
    }

    /// Renaming changes the row's display name without waiting for the next refresh.
    func rename(_ id: String, to name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].name = name
        if let r = rows[id] {
            rows[id] = Row(id: r.id, name: name, plan: r.plan, h5: r.h5, h5Reset: r.h5Reset, d7: r.d7, d7Reset: r.d7Reset,
                           trendPerDay: r.trendPerDay, today: r.today, status: r.status, fetchedAt: r.fetchedAt)
        }
        writeSnapshot(force: true)
    }

    // MARK: Widget snapshot

    /// Only this app may write the app-group container. WidgetKit allows roughly 40-70 reloads a day, so the
    /// widget reloads only when something it shows changed, at most once per 15 min, unless the user asked.
    /// (Between reloads its own timeline keeps countdowns moving.)
    func writeSnapshot(force: Bool = false) {
        if force { forceWidgetReload = true }
        let rows = visibleRows
        let now = Date.now
        let series = Dictionary(uniqueKeysWithValues: rows.map {
            ($0.id, Alerts.series(history, id: $0.id, current: $0.d7, since: now - 28 * 86400, now: now))
        })
        self.series = series
        let snap = Snapshot(updated: lastRefresh ?? now, nextUpdate: nextRefresh ?? now + interval, rows: rows, series: series)
        guard let file = Snapshot.file, let data = try? JSONEncoder.usage.encode(snap) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        let key = Self.widgetKey(rows)
        if forceWidgetReload || (key != lastWidgetKey && Date.now.timeIntervalSince(lastWidgetReload) >= 15 * 60) {
            WidgetCenter.shared.reloadAllTimelines()
            lastWidgetKey = key
            lastWidgetReload = .now
            forceWidgetReload = false
        }
    }

    /// What the widget actually draws: whole percents, reset minutes, names, plans, statuses, order.
    nonisolated static func widgetKey(_ rows: [Row]) -> String {
        rows.map { r in
            [r.id, r.name, r.plan, r.status.rawValue,
             r.h5.map { "\(Int($0.rounded()))" } ?? "-", r.d7.map { "\(Int($0.rounded()))" } ?? "-",
             r.h5Reset.map { "\(Int($0.timeIntervalSince1970 / 60))" } ?? "-",
             r.d7Reset.map { "\(Int($0.timeIntervalSince1970 / 60))" } ?? "-"].joined(separator: "|")
        }.joined(separator: "\n")
    }

    // MARK: Notifications

    private func notify(now: Date) {
        var sent = Set(defaults.stringArray(forKey: "sentAlerts") ?? [])
        let alerts = Alerts.evaluate(rows: visibleRows, history: history, settings: alertSettings, sent: sent, now: now)
        for a in alerts {
            let c = UNMutableNotificationContent()
            c.title = a.title
            c.body = a.body
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: a.key, content: c, trigger: nil))
            sent.insert(a.key)
        }
        // Keys embed their window, so old ones never match again; keep the list short
        defaults.set(Array(Array(sent).suffix(400)), forKey: "sentAlerts")  // an ArraySlice isn't a plist type
    }

    // MARK: System events

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Store.shared.timer?.invalidate() }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            // Give the network a moment after wake
            Task { @MainActor in try? await Task.sleep(for: .seconds(5)); Store.shared.refreshNow(byUser: false) }
        }
        // The widget's refresh button posts this (a sandboxed extension can't fetch itself)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            log.info("refresh signal")
            Task { @MainActor in Store.shared.refreshNow() }
        }, RefreshSignal.name as CFString, nil, .deliverImmediately)
        log.info("observing refresh signal")
    }

    // MARK: Persistence helpers

    private func save<T: Encodable>(_ value: T, _ key: String) { defaults.set(try? JSONEncoder().encode(value), forKey: key) }
    private func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

/// Local usage history (JSON lines in Application Support), kept 35 days, for "today" and burn-rate alerts.
enum History {
    static let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentsUsageWatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.jsonl")
    }()

    static func load() -> [Sample] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let d = JSONDecoder.usage
        return text.split(separator: "\n").compactMap { try? d.decode(Sample.self, from: Data($0.utf8)) }
    }

    /// Appends when the value changed or 10 min passed since this account's last sample (keeps the file small).
    static func append(_ s: Sample, to history: inout [Sample]) {
        if let last = history.last(where: { $0.id == s.id }), last.d7 == s.d7, last.r == s.r, s.t.timeIntervalSince(last.t) < 600 { return }
        history.append(s)
        guard let line = try? JSONEncoder.usage.encode(s), let h = (try? FileHandle(forWritingTo: file)) ?? create() else { return }
        h.seekToEndOfFile(); h.write(line + Data("\n".utf8)); try? h.close()
    }

    /// Drops samples older than 35 days, rewriting the file at most once a day.
    static func prune(_ history: inout [Sample], now: Date) {
        guard let first = history.first, now.timeIntervalSince(first.t) > 36 * 86400 else { return }
        history.removeAll { now.timeIntervalSince($0.t) > 35 * 86400 }
        let e = JSONEncoder.usage
        let text = history.compactMap { try? e.encode($0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        try? (text + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private static func create() -> FileHandle? {
        FileManager.default.createFile(atPath: file.path, contents: nil)
        return try? FileHandle(forWritingTo: file)
    }
}
