import CryptoKit
import Foundation

/// One account's latest windows, from whichever source this build uses.
enum FetchResult {
    case ok(Parse.Windows, plan: String, at: Date)
    case failed(Row.Status, plan: String?, retryAfter: TimeInterval?)
}

/// Claude limits from Claude Code's own status line data. Claude Code pipes a JSON status to its
/// `statusLine` command after each message, including `rate_limits`; our helper script saves that part to
/// ~/.agentsusagewatch/claude/<key>.json and then runs the user's previous status line command.
/// Nothing is fetched over the network, so values are only as fresh as the last Claude Code message.
enum StatusLine {
    static let root = URL(fileURLWithPath: Accounts.home + "/.agentsusagewatch", isDirectory: true)
    static let helper = root.appendingPathComponent("statusline")
    static let dataDir = root.appendingPathComponent("claude", isDirectory: true)

    /// Same key the helper computes: sha256 of the config folder path, first 16 hex chars.
    static func key(_ configDir: String) -> String {
        SHA256.hash(data: Data(configDir.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// Older than this, the values are shown as "as of" the last Claude Code use.
    static let idleAfter: TimeInterval = 2 * 3600

    static func read(_ account: Account, now: Date = .now) -> FetchResult {
        let file = dataDir.appendingPathComponent(key(account.id) + ".json")
        guard let data = try? Data(contentsOf: file) else {
            return .failed(isConnected(account) ? .waiting : .notConnected, plan: account.plan, retryAfter: nil)
        }
        guard let w = Parse.statusLine(data) else { return .failed(.apiChanged, plan: account.plan, retryAfter: nil) }
        let at = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
        return .ok(w, plan: account.plan ?? "-", at: at)
    }

    // MARK: Setup (only when the user clicks Connect)

    /// Copies the bundled helper to a path without spaces, so it can go in settings.json unquoted.
    static func installHelper() {
        guard let src = Bundle.main.url(forResource: "statusline", withExtension: "sh"),
              let new = try? Data(contentsOf: src) else { return }
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        if (try? Data(contentsOf: helper)) != new {
            try? new.write(to: helper, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        }
    }

    /// The real settings file. Several config folders often symlink one shared settings.json, and writing
    /// through the link would replace it with a copy.
    static func settingsFile(_ account: Account) -> URL {
        URL(fileURLWithPath: account.id + "/settings.json").resolvingSymlinksInPath()
    }

    static func isConnected(_ account: Account) -> Bool {
        command(in: settings(settingsFile(account))) == helper.path
    }

    /// Points statusLine at the helper and remembers the previous command for every account sharing this
    /// settings file, so each keeps its old status line output. Backs the file up once first.
    static func connect(_ account: Account, all accounts: [Account]) throws {
        installHelper()
        let file = settingsFile(account)
        var s = settings(file)
        let previous = command(in: s)
        guard previous != helper.path else { return }
        let backup = file.appendingPathExtension("agentsusagewatch-backup")
        if FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: file, to: backup)
        }
        for a in accounts where settingsFile(a) == file {
            let next = dataDir.appendingPathComponent(key(a.id) + ".next")
            if let previous { try Data(previous.utf8).write(to: next, options: .atomic) }
            else { try? FileManager.default.removeItem(at: next) }
        }
        var line = s["statusLine"] as? [String: Any] ?? [:]
        line["type"] = "command"
        line["command"] = helper.path
        s["statusLine"] = line
        try write(s, to: file)
    }

    /// Puts the previous status line command back (or removes ours if there was none).
    static func disconnect(_ account: Account, all accounts: [Account]) throws {
        let file = settingsFile(account)
        var s = settings(file)
        guard command(in: s) == helper.path else { return }
        let next = dataDir.appendingPathComponent(key(account.id) + ".next")
        if let previous = try? String(contentsOf: next, encoding: .utf8), !previous.isEmpty {
            var line = s["statusLine"] as? [String: Any] ?? [:]
            line["command"] = previous
            s["statusLine"] = line
        } else {
            s["statusLine"] = nil
        }
        try write(s, to: file)
        for a in accounts where settingsFile(a) == file {
            try? FileManager.default.removeItem(at: dataDir.appendingPathComponent(key(a.id) + ".next"))
        }
    }

    private static func settings(_ file: URL) -> [String: Any] {
        (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    private static func command(in s: [String: Any]) -> String? {
        (s["statusLine"] as? [String: Any])?["command"] as? String
    }

    private static func write(_ s: [String: Any], to file: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
