// Self-check for the pure logic (parser, alerts, model maths), from fixtures — runs anywhere:
// F="Shared/Model.swift App/Parse.swift App/Alerts.swift App/Accounts.swift App/StatusLine.swift Checks/ModelCheck/main.swift"
// swiftc -o /tmp/chk $F && /tmp/chk                  # public build
// swiftc -D TESTING -o /tmp/chk $F && /tmp/chk       # -testing build (adds the token-source checks)
import Foundation

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { print("FAIL line \(line): \(what)"); exit(1) }
}
let now = Date(timeIntervalSince1970: 1_800_000_000)
func data(_ s: String) -> Data { Data(s.utf8) }

// MARK: Parse — Claude Code status line rate_limits (shape seen on 2026-10-31)
let sl = Parse.statusLine(data(#"{"five_hour":{"used_percentage":19,"resets_at":1793490600},"seven_day":{"used_percentage":23.5,"resets_at":1793854800}}"#))
check(sl?.h5 == 19 && sl?.d7 == 23.5 && sl?.d7Reset == Date(timeIntervalSince1970: 1793854800), "status line windows parse")
let slUltra = Parse.statusLine(data(#"{"seven_day":{"used_percentage":47,"resets_at":1793750400}}"#))
check(slUltra?.d7 == 47 && slUltra?.h5 == nil, "Ultra: no five_hour in the status line")
check(Parse.statusLine(data(#"{"something_new":{}}"#)) == nil && Parse.statusLine(data("not json")) == nil, "unrecognised -> nil")
check(Parse.plan(tier: "default_claude_max_20x", subscription: nil) == "ultra" && Parse.plan(tier: "default_claude_max_5x", subscription: nil) == "max",
      "plan from oauthAccount tier")

// MARK: The helper script, end to end: saves rate_limits under the key the app reads, and still runs the old command
do {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("auw-check-\(getpid())")
    let out = tmp.appendingPathComponent(".agentsusagewatch/claude")
    try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let dir = "/Users/x/.claude-work"
    try! Data("cat >/dev/null; echo previous-status-line".utf8).write(to: out.appendingPathComponent(StatusLine.key(dir) + ".next"))
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["App/Resources/statusline.sh"]
    p.environment = ["HOME": tmp.path, "CLAUDE_CONFIG_DIR": dir + "/"]
    let input = Pipe(), output = Pipe(); p.standardInput = input; p.standardOutput = output
    try! p.run()
    input.fileHandleForWriting.write(data(#"{"model":{"id":"m"},"rate_limits":{"seven_day":{"used_percentage":12,"resets_at":1793854800}}}"#))
    try! input.fileHandleForWriting.close()
    p.waitUntilExit()
    let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let saved = try? Data(contentsOf: out.appendingPathComponent(StatusLine.key(dir) + ".json"))
    check(saved.flatMap(Parse.statusLine)?.d7 == 12, "helper saved rate_limits under the app's key (trailing slash ignored)")
    check(printed == "previous-status-line\n", "helper still prints the previous status line")
    try? FileManager.default.removeItem(at: tmp)
}

#if TESTING
// MARK: Parse — usage responses (shapes seen on 2026-10-31, values trimmed)
let ultra = data("""
{"five_hour":null,"seven_day":{"utilization":47.0,"resets_at":"2026-11-04T00:00:00.138407+00:00"},
 "limits":[{"kind":"weekly_all","percent":47,"resets_at":"2026-11-04T00:00:00.138407+00:00","scope":null},
           {"kind":"weekly_scoped","percent":0,"resets_at":"2026-11-04T00:00:00+00:00","scope":{"model":{"display_name":"Fable"}}}]}
""")
let u = Parse.usage(ultra)
check(u?.d7 == 47 && u?.h5 == nil && u?.h5Reset == nil, "Ultra: weekly from limits[], no 5h window")
check(u?.d7Reset == Parse.date("2026-11-04T00:00:00Z")?.addingTimeInterval(0.138407) || abs((u?.d7Reset?.timeIntervalSince1970 ?? 0) - 1793750400.138) < 0.01,
      "fractional-second dates parse")

let maxPlan = data("""
{"five_hour":{"utilization":5.0,"resets_at":"2026-10-31T18:49:59.745001+00:00"},"seven_day":{"utilization":9.0,"resets_at":"2026-11-05T04:59:59.745019+00:00"},
 "limits":[{"kind":"session","percent":7,"resets_at":"2026-10-31T18:49:59.745001+00:00"},{"kind":"weekly_all","percent":8,"resets_at":"2026-11-05T04:59:59.745019+00:00"}]}
""")
let m = Parse.usage(maxPlan)
check(m?.h5 == 7 && m?.d7 == 8, "limits[] wins over the old fields")
check(Parse.usage(data(#"{"five_hour":{"utilization":12},"seven_day":{"utilization":30,"resets_at":"2026-11-05T05:00:00Z"}}"#))?.d7 == 30,
      "old shape still works")
check(Parse.usage(data(#"{"limits":[{"kind":"something_new","percent":3}],"five_hour":null,"seven_day":null}"#)) == nil,
      "nothing recognisable -> nil (format changed), never a fake 0%")
check(Parse.usage(data("<html>502</html>")) == nil, "HTML error page -> nil")

// MARK: Parse — logins and Keychain names
let login = data(#"{"claudeAiOauth":{"accessToken":"t0k","expiresAt":1793483427754,"rateLimitTier":"default_claude_max_20x","subscriptionType":"max"}}"#)
let c = Parse.credentials(login)
check(c?.accessToken == "t0k" && c?.plan == "ultra" && abs((c?.expiresAt?.timeIntervalSince1970 ?? 0) - 1793483427.754) < 0.01, "login parses")
check(Parse.plan(tier: "default_claude_max_5x", subscription: "max") == "max", "max 5x -> max")
check(Parse.plan(tier: nil, subscription: "pro") == "pro", "unknown tier falls back to subscription")
check(Parse.credentials(data(#"{"claudeAiOauth":{"accessToken":""}}"#)) == nil, "empty token -> nil")
check(Parse.keychainService(configDir: "/Users/x/.claude", home: "/Users/x") == "Claude Code-credentials", "default login name")
// Same hash Claude Code uses: printf '%s' "$dir" | shasum -a 256 | cut -c1-8
check(Parse.keychainService(configDir: "/Users/x/.claude-work", home: "/Users/x")
      == "Claude Code-credentials-" + String(Process.sha8("/Users/x/.claude-work")), "hashed name")
#endif

// MARK: Model
func row(_ id: String = "a", d7: Double?, resetIn: TimeInterval?, h5: Double? = nil, h5ResetIn: TimeInterval? = nil, status: Row.Status = .ok) -> Row {
    Row(id: id, name: id.uppercased(), plan: "max", h5: h5, h5Reset: h5ResetIn.map { now + $0 }, d7: d7,
        d7Reset: resetIn.map { now + $0 }, trendPerDay: nil, today: nil, status: status, fetchedAt: now)
}
let half = row(d7: 40, resetIn: Usage.week / 2)
check(abs(half.weekElapsed(at: now)! - 0.5) < 1e-9 && abs(half.projectedWeekly(at: now)! - 80) < 1e-9, "projection")
check(row(d7: 5, resetIn: Usage.week - 3600).projectedWeekly(at: now) == nil, "no projection in a fresh week")
let passed = row(d7: 70, resetIn: -60, h5: 50, h5ResetIn: 600).applyingResets(at: now)
check(passed.d7 == 0 && passed.h5 == 50, "a passed reset empties only that window")
check(Usage.countdown(to: now + 4*86400 + 3*3600 + 59, from: now) == "4d 3h" && Usage.countdown(to: now + 2*3600 + 5*60, from: now) == "2h 05m"
      && Usage.countdown(to: now + 30, from: now) == "now", "countdown")
check(Usage.tone(59.9) == .ok && Usage.tone(60) == .warn && Usage.tone(85) == .critical, "tones")

// MARK: Alerts
var s = AlertSettings(); s.quietFrom = nil; s.quietTo = nil
let hot = row(d7: 86, resetIn: Usage.week / 2, h5: 96, h5ResetIn: 3600)
let a1 = Alerts.evaluate(rows: [hot], history: [], settings: s, sent: [], now: now)
check(a1.filter { $0.title.contains("5-hour") }.count == 1 && a1.contains { $0.key.hasSuffix("|95") && $0.title.contains("5-hour") },
      "only the highest crossed 5h threshold")
check(a1.contains { $0.key.contains("|runout|") }, "86% at mid-week -> run-out alert")
check(Alerts.evaluate(rows: [hot], history: [], settings: s, sent: Set(a1.map(\.key)), now: now).isEmpty, "sent alerts never repeat")
check(Alerts.evaluate(rows: [row(d7: 86, resetIn: Usage.week / 2, status: .expired)], history: [], settings: s, sent: [], now: now).isEmpty,
      "no alerts from stale values")
let lazy = Alerts.evaluate(rows: [row(d7: 10, resetIn: Usage.week * 0.4)], history: [], settings: s, sent: [], now: now)
check(lazy.count == 1 && lazy[0].title.contains("only 17%"), "mid-week underuse forecast")

var q = s; q.quietFrom = 23; q.quietTo = 8
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
let at = { (h: Int) in cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: h))! }
check(Alerts.inQuietHours(at(23), q, calendar: cal) && Alerts.inQuietHours(at(3), q, calendar: cal)
      && !Alerts.inQuietHours(at(8), q, calendar: cal) && !Alerts.inQuietHours(at(15), q, calendar: cal), "quiet hours across midnight")

// Burn rate: 7 days of ~1%/active hour, then +6% in the last hour
let wk = now + Usage.week / 2
var hist: [Sample] = []
var level = 0.0
for h in stride(from: 7 * 24, to: 1, by: -1) where h % 8 < 3 {  // 3 active hours out of every 8
    let t = now - Double(h) * 3600
    hist.append(Sample(t: t, id: "a", d7: level, r: wk)); level += 1
    hist.append(Sample(t: t + 1800, id: "a", d7: level, r: wk))
}
check(Alerts.burnSpike(hist, now: now) == nil, "normal pace -> no spike")
hist.append(Sample(t: now - 3000, id: "a", d7: level, r: wk))
hist.append(Sample(t: now - 60, id: "a", d7: level + 6, r: wk))
let spike = Alerts.burnSpike(hist, now: now)
check(spike != nil && abs(spike!.lastHour - 6) < 1e-9, "6× usual in the last hour -> spike")
check(Alerts.burnSpike(Array(hist.suffix(4)), now: now) == nil, "no spike alert without a baseline")
check(Alerts.hourlyGains([Sample(t: now, id: "a", d7: 90, r: now), Sample(t: now + 60, id: "a", d7: 2, r: now + Usage.week)]).isEmpty,
      "a weekly reset isn't counted as usage")

// MARK: Progress series
let samples = (0..<12).map { Sample(t: now - Double(12 - $0) * 1800, id: "a", d7: Double($0), r: nil) }   // every 30 min
    + [Sample(t: now - 600, id: "b", d7: 99, r: nil), Sample(t: now - 40 * 86400, id: "a", d7: 1, r: nil)]
let ser = Alerts.series(samples, id: "a", current: 12, since: now - 28 * 86400, now: now)
check(ser.count <= 5 && ser.last == Point(t: now, v: 12), "one point per 2 h bucket, ending at the current value")
check(ser.allSatisfy { $0.v != 99 && $0.v != 1 }, "other accounts and samples older than the window are left out")
check(zip(ser, ser.dropFirst()).allSatisfy { $0.t < $1.t }, "points in time order")

print("ok: all checks passed")

extension Process {
    /// sha256(s)[:8] via shasum, to cross-check Parse.keychainService against claude-smart's shell formula.
    static func sha8(_ s: String) -> Substring {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "printf '%s' \"$0\" | shasum -a 256 | cut -c1-8", s]
        let pipe = Pipe(); p.standardOutput = pipe
        try! p.run(); p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).prefix(8)
    }
}
