import Foundation
import SQLite3

/// A Claude Code login, identified by its config folder (stable across renames).
struct Account: Codable, Identifiable, Equatable {
    let id: String          // standardized config folder path
    var name: String
    var email: String?
    var accountUuid: String?
    var plan: String?       // "ultra", "max", "pro"… from Claude Code's account info; nil if unknown
    var hidden = false      // hidden from the menu bar panel, menu bar value and alerts
    var widgetHidden: Bool? // hidden from the widgets; nil follows `hidden` (how it behaved before this setting)
    var manual = false      // added by the user (can be removed); discovered ones come back on rescan
    var provider: String?   // nil = Claude Code, "codex" = OpenAI Codex CLI

    var inMenu: Bool { !hidden }
    var inWidgets: Bool { !(widgetHidden ?? hidden) }

    var isCodex: Bool { provider == "codex" }
    var isAntigravity: Bool { provider == "antigravity" }
    var isClaude: Bool { provider == nil }
    var usesStatusLine: Bool { isClaude || isAntigravity }   // limits arrive through a status line helper

    var isDefault: Bool { id == Accounts.home + "/.claude" }
#if TESTING
    var keychainService: String { Parse.keychainService(configDir: id, home: Accounts.home) }
#endif
}

enum Accounts {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// ~/.claude plus every ~/.claude-* folder where Claude Code is logged in (its account info file has an
    /// `oauthAccount`). Folders are the starting point because a Keychain hash can't be traced to its folder.
    static func discover() -> [Account] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
        let dirs = [home + "/.claude"] + names.filter { $0.hasPrefix(".claude-") }.sorted().map { home + "/" + $0 }
        // Codex is detected on its own: logged in when ~/.codex/auth.json holds a login
        return Providers.discover() + dirs.compactMap { dir in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
            let a = make(dir)
            return a.email != nil || a.accountUuid != nil ? a : nil
        }
    }

    static func make(_ dir: String, manual: Bool = false) -> Account {
        let path = (dir as NSString).standardizingPath
        if Codex.isFolder(path) {
            return Account(id: path, name: "CODEX", email: Codex.login(path)?.email, plan: nil, manual: manual, provider: "codex")
        }
        // Default name: last dash-separated part, uppercased (~/.claude-account-work -> WORK)
        let base = (path as NSString).lastPathComponent
        let name = path == home + "/.claude" ? "DEFAULT" : String(base.split(separator: "-").last ?? Substring(base)).uppercased()
        // The default login keeps its account info in ~/.claude.json, others inside their folder
        let info = path == home + "/.claude" ? home + "/.claude.json" : path + "/.claude.json"
        let o = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: info)))) as? [String: Any]
        let oauth = o?["oauthAccount"] as? [String: Any]
        let tier = oauth?["organizationRateLimitTier"] as? String ?? oauth?["userRateLimitTier"] as? String
        return Account(id: path, name: name, email: oauth?["emailAddress"] as? String,
                       accountUuid: oauth?["accountUuid"] as? String,
                       plan: tier.map { Parse.plan(tier: $0, subscription: nil) }, manual: manual)
    }

    /// Merge a fresh discovery into the saved list: keep the user's names/order/hidden flags, add new
    /// folders at the end (hiding one that is the same login as an account already listed, e.g. ~/.claude
    /// usually duplicates one of the named accounts), drop discovered folders that disappeared.
    static func merge(saved: [Account], found: [Account]) -> [Account] {
        var out = saved.filter { s in s.manual || found.contains { $0.id == s.id } }
        for f in found where !out.contains(where: { $0.id == f.id }) {
            var a = f
            // ~/.claude is usually the same login as one of the named folders: hide it, never the named one
            if a.isDefault, let u = a.accountUuid, found.contains(where: { !$0.isDefault && $0.accountUuid == u }) {
                a.hidden = true
            }
            out.append(a)
        }
        // Refresh emails/uuids/plans (a folder can be logged into another account, or change plan)
        return out.map { s in
            guard let f = found.first(where: { $0.id == s.id }) ?? (s.manual ? make(s.id, manual: true) : nil) else { return s }
            var a = s; a.email = f.email; a.accountUuid = f.accountUuid; a.plan = f.plan; a.provider = f.provider
            if a.isCodex, a.name == ".CODEX" { a.name = "CODEX" }   // was added as a plain folder
            return a
        }
    }
}

/// Agents whose limits are read from local files (not Claude Code). To add one: a reader like `Codex` below,
/// and one line in each of these two functions. Everything else (rows, widget, alerts, settings) is generic.
enum Providers {
    /// Accounts to show without the user adding a folder.
    static func discover() -> [Account] {
        [Codex.login(Codex.dir) != nil ? Accounts.make(Codex.dir) : nil].compactMap { $0 }
            + Antigravity.discover() + OpenCode.discover()
    }

    /// nil = Claude Code (status line / testing fetcher).
    static func read(_ account: Account) -> FetchResult? {
        switch account.provider {
        case "codex": Codex.read(account)
        case "antigravity": Antigravity.read(account)
        case "opencode": OpenCode.read(account)
        default: nil
        }
    }
}

/// Antigravity CLI (`agy`): like Claude Code it pipes a status JSON, including `quota`, to a configured
/// `statusLine` command, so the same Set Up helper trick works (no tokens, no network). Two accounts share one
/// login: Gemini models, and third-party models (Claude, GPT-OSS) which have their own 5-hour and weekly limits.
enum Antigravity {
    static let dir = Accounts.home + "/.gemini/antigravity-cli"
    static let thirdPartySuffix = "#3p"
    static var dataFile: URL { StatusLine.root.appendingPathComponent("antigravity/quota.json") }

    static func discover() -> [Account] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return [] }
        return [Account(id: dir, name: "ANTIGRAVITY", plan: nil, provider: "antigravity"),
                Account(id: dir + thirdPartySuffix, name: "ANTIGRAVITY 3P", plan: nil, hidden: true, provider: "antigravity")]
    }

    static func read(_ account: Account) -> FetchResult {
        let family = account.id.hasSuffix(thirdPartySuffix) ? "3p" : "gemini"
        guard let data = try? Data(contentsOf: dataFile) else {
            return .failed(StatusLine.isConnected(account) ? .waiting : .notConnected, plan: account.plan, retryAfter: nil)
        }
        guard let r = Parse.antigravity(data, family: family) else { return .failed(.apiChanged, plan: account.plan, retryAfter: nil) }
        let at = (try? dataFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        // "Google AI Pro" -> "Pro", so the chip stays short
        let plan = r.plan?.replacingOccurrences(of: "Google AI ", with: "")
        return .ok(r.windows, plan: plan ?? account.plan ?? "-", at: at)
    }
}

/// opencode: no plan limit, so show what it spent. Read-only from its own SQLite database.
enum OpenCode {
    static let dir = Accounts.home + "/.local/share/opencode"
    static var db: String { dir + "/opencode.db" }

    static func discover() -> [Account] {
        FileManager.default.fileExists(atPath: db) ? [Account(id: dir, name: "OPENCODE", plan: "-", provider: "opencode")] : []
    }

    static func read(_ account: Account, now: Date = .now) -> FetchResult {
        let startOfDay = Calendar.current.startOfDay(for: now)
        guard let today = totals(since: startOfDay, db: account.id + "/opencode.db"),
              let week = totals(since: now - 7 * 86400, db: account.id + "/opencode.db") else {
            return .failed(.error, plan: nil, retryAfter: nil)
        }
        return .spend(Spend(tokensToday: today.tokens, tokensWeek: week.tokens, costToday: today.cost, costWeek: week.cost),
                      at: week.last ?? .distantPast)
    }

    /// Assistant messages since a date: tokens (input + output + reasoning; cache reads would swamp the count),
    /// cost, and the newest message time. nil = couldn't read the database.
    static func totals(since: Date, db path: String) -> (tokens: Int, cost: Double, last: Date?)? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        let sql = """
            SELECT COALESCE(SUM(COALESCE(json_extract(data,'$.tokens.input'),0) + COALESCE(json_extract(data,'$.tokens.output'),0)
                              + COALESCE(json_extract(data,'$.tokens.reasoning'),0)), 0),
                   COALESCE(SUM(COALESCE(json_extract(data,'$.cost'),0)), 0), MAX(time_created)
            FROM message WHERE json_extract(data,'$.role') = 'assistant' AND time_created >= ?
            """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, Int64(since.timeIntervalSince1970 * 1000))
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        let last = sqlite3_column_type(st, 2) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: Double(sqlite3_column_int64(st, 2)) / 1000)
        return (Int(sqlite3_column_int64(st, 0)), sqlite3_column_double(st, 1), last)
    }
}

/// OpenAI Codex CLI: limits come from the rate_limits Codex writes into its own session logs, so no network
/// and no token use. They update while Codex runs, like Claude's status line.
enum Codex {
    static let dir = Accounts.home + "/.codex"

    static func isFolder(_ path: String) -> Bool {
        let fm = FileManager.default
        return (path as NSString).lastPathComponent == ".codex"
            || (fm.fileExists(atPath: path + "/auth.json") && fm.fileExists(atPath: path + "/sessions"))
    }

    /// nil = not logged in (no auth.json, or neither a ChatGPT login nor an API key in it).
    static func login(_ path: String) -> (email: String?, Void)? {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: path + "/auth.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let tokens = o["tokens"] as? [String: Any]
        guard (tokens?["access_token"] as? String).map({ !$0.isEmpty }) == true || (o["OPENAI_API_KEY"] as? String).map({ !$0.isEmpty }) == true
        else { return nil }
        return (email(idToken: tokens?["id_token"] as? String), ())
    }

    /// The id_token is a JWT; its payload has the account email.
    static func email(idToken: String?) -> String? {
        guard let part = idToken?.split(separator: ".").dropFirst().first else { return nil }
        var b64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let d = Data(base64Encoded: b64), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o["email"] as? String
    }

    static func read(_ account: Account) -> FetchResult {
        guard login(account.id) != nil else { return .failed(.notLoggedIn, plan: nil, retryAfter: nil) }
        guard let r = latest(in: account.id + "/sessions") else { return .failed(.waiting, plan: nil, retryAfter: nil) }
        return .ok(r.windows, plan: r.plan ?? account.plan ?? "-", at: r.at ?? .now)
    }

    /// Newest rate_limits event: scan the tail of the most recently written session logs.
    private static func latest(in sessions: String) -> (windows: Parse.Windows, plan: String?, at: Date?)? {
        let fm = FileManager.default
        var files: [(URL, Date)] = []
        for case let url as URL in fm.enumerator(at: URL(fileURLWithPath: sessions), includingPropertiesForKeys: [.contentModificationDateKey]) ?? NSEnumerator()
        where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            files.append((url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast))
        }
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(8) {
            guard let h = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? h.close() }
            let size = (try? h.seekToEnd()) ?? 0
            try? h.seek(toOffset: size > 524_288 ? size - 524_288 : 0)
            let tail = h.readDataToEndOfFile()
            for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
                if let r = Parse.codex(Data(line)) { return r }
            }
        }
        return nil
    }
}

#if TESTING
enum Keychain {
    /// Claude Code writes its login with /usr/bin/security, so reading it through the same tool doesn't
    /// prompt (CodexBar reads it the same way).
    static func read(_ service: String) -> Data? {
        let out = run("/usr/bin/security", ["find-generic-password", "-s", service, "-w"])
        return out.status == 0 ? out.data : nil
    }

    /// Existence check without reading the secret.
    static func exists(_ service: String) -> Bool {
        run("/usr/bin/security", ["find-generic-password", "-s", service]).status == 0
    }
}
#endif

/// Runs a tool and returns its exit status and stdout. A timeout kills it (a hung tool must not hang refresh).
@discardableResult
func run(_ path: String, _ args: [String], env: [String: String]? = nil, timeout: TimeInterval = 15) -> (status: Int32, data: Data) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if let env { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, Data()) }
    let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    killer.cancel()
    return (p.terminationStatus, data)
}
