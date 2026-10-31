import Foundation

extension Bundle {
    var version: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
}

#if TESTING
// Private -testing builds only (./install.sh --testing). Public builds don't contain this file's code.

/// One account's refresh: Keychain -> (optional login wake-up) -> usage endpoint -> parsed windows.
enum Fetcher {
    static func fetch(_ account: Account, wakeExpired: Bool) async -> FetchResult {
        guard var creds = Keychain.read(account.keychainService).flatMap(Parse.credentials) else {
            return .failed(.notLoggedIn, plan: nil, retryAfter: nil)
        }
        if let exp = creds.expiresAt, exp < .now + 60 {
            // Access tokens last ~8h. Let Claude Code itself refresh the login (it saves the rotated token);
            // refreshing it here would rotate the token behind Claude Code's back and log it out.
            guard wakeExpired, await wake(account), let fresh = Keychain.read(account.keychainService).flatMap(Parse.credentials),
                  (fresh.expiresAt ?? .distantFuture) > .now + 60 else {
                return .failed(.expired, plan: creds.plan, retryAfter: nil)
            }
            creds = fresh
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("AgentsUsageWatch/\(Bundle.main.version) (local widget)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            switch http?.statusCode ?? 0 {
            case 200:
                guard let w = Parse.usage(data) else { return .failed(.apiChanged, plan: creds.plan, retryAfter: nil) }
                return .ok(w, plan: creds.plan, at: .now)
            case 401, 403:
                return .failed(.expired, plan: creds.plan, retryAfter: nil)
            case 429:
                let ra = (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
                return .failed(.rateLimited, plan: creds.plan, retryAfter: ra)
            default:
                return .failed(.error, plan: creds.plan, retryAfter: nil)
            }
        } catch {
            return .failed((error as? URLError)?.code == .notConnectedToInternet ? .offline : .error, plan: creds.plan, retryAfter: nil)
        }
    }

    // One wake-up per account per 30 min, so a broken login doesn't spawn claude on every refresh
    private static var lastWake: [String: Date] = [:]
    private static let lock = NSLock()

    /// True (and records the time) if this account wasn't woken in the last 30 min.
    private static func claimWake(_ id: String) -> Bool {
        lock.withLock {
            if let last = lastWake[id], last > .now - 1800 { return false }
            lastWake[id] = .now
            return true
        }
    }

    /// A tiny haiku request through the user's own Claude Code, which refreshes and saves the login.
    private static func wake(_ account: Account) async -> Bool {
        guard claimWake(account.id), let claude = claudePath else { return false }
        let env = account.isDefault ? [:] : ["CLAUDE_CONFIG_DIR": account.id]
        return await Task.detached {
            run(claude, ["-p", "--model", "haiku", "--max-turns", "1", "--strict-mcp-config",
                         "--no-session-persistence", "reply ok"], env: env, timeout: 45).status == 0
        }.value
    }

    /// Apps started from Finder get a minimal PATH, so look in the usual install spots.
    static let claudePath: String? = {
        let home = Accounts.home
        return [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", home + "/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()
}
#endif
