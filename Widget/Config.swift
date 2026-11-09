import AppIntents
import WidgetKit

// Right-click the widget > Edit "Agents Usage Watch" to change these.
struct ConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Agents Usage Watch"
    static let description = IntentDescription("Choose which accounts to show and how the widget looks.")

    @Parameter(title: "Accounts", description: "Leave empty to show every account.")
    var accounts: [AccountEntity]?

    @Parameter(title: "Background", default: .standard)
    var background: BackgroundStyle

    @Parameter(title: "Weekly pace marker", default: true)
    var showPace: Bool

    @Parameter(title: "Trend & projection", default: true)
    var showTrend: Bool

    var accountIds: [String] { accounts?.map(\.id) ?? [] }
}

enum BackgroundStyle: String, AppEnum {
    case standard, transparent, tinted

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Background"
    static let caseDisplayRepresentations: [BackgroundStyle: DisplayRepresentation] = [
        .standard: "Standard",
        .transparent: "Transparent",
        .tinted: "Tinted",
    ]
}

/// An account, identified by its config folder so renaming it in the app keeps widget choices.
struct AccountEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AccountQuery: EnumerableEntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        let all = try await allEntities()
        return identifiers.map { id in all.first { $0.id == id } ?? AccountEntity(id: id, name: "Removed account") }
    }
    func allEntities() async throws -> [AccountEntity] {
        (Snapshot.load()?.rows ?? []).map { AccountEntity(id: $0.id, name: $0.name) }
    }
}

/// The widget's refresh button. A sandboxed extension can't read the Keychain, so it asks the menu bar app.
struct RefreshIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh usage"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(RefreshSignal.name as CFString), nil, nil, true)
        return .result()
    }
}

// Right-click the widget > Edit "Usage Progress".
struct ProgressIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Usage Progress"
    static let description = IntentDescription("How weekly usage grew over time.")

    @Parameter(title: "Accounts", description: "Leave empty to show every account.")
    var accounts: [AccountEntity]?

    @Parameter(title: "Period", default: .week)
    var period: ProgressPeriod

    @Parameter(title: "Background", default: .standard)
    var background: BackgroundStyle

    var accountIds: [String] { accounts?.map(\.id) ?? [] }
}

enum ProgressPeriod: String, AppEnum {
    case week, month

    var days: Int { self == .week ? 7 : 28 }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static let caseDisplayRepresentations: [ProgressPeriod: DisplayRepresentation] = [
        .week: "This week",
        .month: "Last 4 weeks",
    ]
}

/// Which account the small widgets show; their switch button steps through the chosen accounts.
/// ponytail: one pick per widget kind, so two small widgets of the same kind switch together. Per-instance needs
/// a configuration parameter instead (WidgetKit gives intents no instance id).
enum SmallPick {
    static let defaults = UserDefaults(suiteName: Snapshot.appGroup)
    static func row(_ rows: [Row], kind: String) -> Row { rows[(defaults?.integer(forKey: "pick." + kind) ?? 0) % rows.count] }
    static func advance(_ kind: String) {
        defaults?.set((defaults?.integer(forKey: "pick." + kind) ?? 0) + 1, forKey: "pick." + kind)
    }
}

/// The small widgets' switch button. WidgetKit reloads the widget after it runs.
struct NextAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Show next account"
    static let isDiscoverable = false

    @Parameter(title: "Widget") var kind: String

    init() {}
    init(kind: String) { self.kind = kind }

    func perform() async throws -> some IntentResult {
        SmallPick.advance(kind)
        return .result()
    }
}
