import CryptoKit
import Foundation

// Pure parsing, no I/O, so it's checkable with fixtures (Checks/ModelCheck). Tolerant on purpose: these
// formats belong to other tools and change without notice (Oct 2026: Ultra lost its 5-hour window).
enum Parse {
    struct Windows: Equatable {
        var h5: Double?, h5Reset: Date?
        var d7: Double?, d7Reset: Date?
    }

    /// Claude Code's status line `rate_limits` (saved by the helper script):
    /// {"five_hour":{"used_percentage":19,"resets_at":<epoch s>},"seven_day":{...}}. Either window may be missing
    /// (Ultra has no 5-hour window). nil = nothing recognisable.
    static func statusLine(_ data: Data) -> Windows? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ k: String) -> (Double?, Date?) {
            let o = root[k] as? [String: Any]
            return (number(o?["used_percentage"]), number(o?["resets_at"]).map { Date(timeIntervalSince1970: $0) })
        }
        var w = Windows()
        (w.h5, w.h5Reset) = window("five_hour")
        (w.d7, w.d7Reset) = window("seven_day")
        return w.d7 == nil && w.h5 == nil ? nil : w
    }

    /// Plans were renamed on 2026-10-30 (Max 5x -> Max, Max 20x -> Ultra); Claude Code still stores the old
    /// tier names, both in its login and in `oauthAccount.organizationRateLimitTier`.
    static func plan(tier: String?, subscription: String?) -> String {
        let t = tier ?? ""
        if t.hasSuffix("max_20x") { return "ultra" }
        if t.hasSuffix("max_5x") { return "max" }
        return subscription ?? (t.isEmpty ? "-" : t)
    }

    /// One Codex session log line (~/.codex/sessions/**/rollout-*.jsonl). Token-count events carry
    /// payload.rate_limits {primary, secondary: {used_percent, window_minutes, resets_at}, plan_type}; which window is
    /// primary depends on the plan, so go by window length (<= 10 h = the 5-hour window, else weekly).
    /// nil = not a rate-limit line.
    static func codex(_ line: Data) -> (windows: Windows, plan: String?, at: Date?)? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let rl = (root["payload"] as? [String: Any])?["rate_limits"] as? [String: Any] else { return nil }
        var w = Windows()
        for k in ["primary", "secondary"] {
            guard let o = rl[k] as? [String: Any], let pct = number(o["used_percent"]) else { continue }
            let reset = number(o["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            if (number(o["window_minutes"]) ?? 10080) <= 600 { w.h5 = pct; w.h5Reset = reset } else { w.d7 = pct; w.d7Reset = reset }
        }
        guard w.h5 != nil || w.d7 != nil else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (w, rl["plan_type"] as? String, (root["timestamp"] as? String).flatMap { f.date(from: $0) })
    }

    /// Antigravity CLI status line: `quota` has "<family>-5h" / "<family>-weekly" windows, family "gemini" or "3p"
    /// (third-party models), each {remaining_fraction 0...1, reset_time ISO8601}. Our helper saves
    /// {"quota":{…},"plan":"Google AI Pro"}. Used % = (1 - remaining) * 100. nil = nothing for that family.
    static func antigravity(_ data: Data, family: String) -> (windows: Windows, plan: String?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quota = root["quota"] as? [String: Any] else { return nil }
        let f = ISO8601DateFormatter()
        func window(_ k: String) -> (Double?, Date?) {
            guard let o = quota["\(family)-\(k)"] as? [String: Any], let rem = number(o["remaining_fraction"]) else { return (nil, nil) }
            return (min(max(1 - rem, 0), 1) * 100, (o["reset_time"] as? String).flatMap { f.date(from: $0) })
        }
        var w = Windows()
        (w.h5, w.h5Reset) = window("5h")
        (w.d7, w.d7Reset) = window("weekly")
        return w.h5 == nil && w.d7 == nil ? nil : (w, root["plan"] as? String)
    }

    private static func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

#if TESTING
    // Private -testing builds only: the owner's token-based source. Not compiled into public builds.

    struct Credentials: Equatable {
        let accessToken: String
        let expiresAt: Date?
        let plan: String
    }

    /// Keychain service Claude Code stores a login under: plain for ~/.claude, else suffixed with the first
    /// 8 hex chars of sha256(the exact CLAUDE_CONFIG_DIR string).
    static func keychainService(configDir: String, home: String) -> String {
        if configDir == home + "/.claude" { return "Claude Code-credentials" }
        let hash = SHA256.hash(data: Data(configDir.utf8)).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-" + hash.prefix(8)
    }

    static func credentials(_ data: Data) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let o = root["claudeAiOauth"] as? [String: Any],
              let token = o["accessToken"] as? String, !token.isEmpty else { return nil }
        let exp = (o["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credentials(accessToken: token, expiresAt: exp,
                           plan: plan(tier: o["rateLimitTier"] as? String, subscription: o["subscriptionType"] as? String))
    }

    /// nil = nothing recognisable (the format changed): keep the last good values instead of showing 0%.
    static func usage(_ data: Data) -> Windows? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var w = Windows()
        // New shape first: limits[] with kind session (5h) / weekly_all (7d)
        for l in root["limits"] as? [[String: Any]] ?? [] {
            let pct = number(l["percent"]), reset = date(l["resets_at"])
            switch l["kind"] as? String {
            case "session": w.h5 = pct; w.h5Reset = reset
            case "weekly_all": w.d7 = pct; w.d7Reset = reset
            default: break
            }
        }
        // Old shape as fallback, field by field
        if w.d7 == nil, let s = root["seven_day"] as? [String: Any] { w.d7 = number(s["utilization"]); w.d7Reset = date(s["resets_at"]) }
        if w.h5 == nil, let s = root["five_hour"] as? [String: Any] { w.h5 = number(s["utilization"]); w.h5Reset = date(s["resets_at"]) }
        return w.d7 == nil && w.h5 == nil ? nil : w
    }

    /// The API sends fractional seconds ("…14:19:59.559235+00:00"), which Swift's plain .iso8601 rejects.
    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
#endif
}
