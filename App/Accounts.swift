import Foundation

/// A Claude Code login, identified by its config folder (stable across renames).
struct Account: Codable, Identifiable, Equatable {
    let id: String          // standardized config folder path
    var name: String
    var email: String?
    var accountUuid: String?
    var plan: String?       // "ultra", "max", "pro"… from Claude Code's account info; nil if unknown
    var hidden = false
    var manual = false      // added by the user (can be removed); discovered ones come back on rescan

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
        return dirs.compactMap { dir in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
            let a = make(dir)
            return a.email != nil || a.accountUuid != nil ? a : nil
        }
    }

    static func make(_ dir: String, manual: Bool = false) -> Account {
        let path = (dir as NSString).standardizingPath
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
            var a = s; a.email = f.email; a.accountUuid = f.accountUuid; a.plan = f.plan; return a
        }
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
