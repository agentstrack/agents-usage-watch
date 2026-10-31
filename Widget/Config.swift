import AppIntents
import WidgetKit

// Right-click the widget > Edit "AgentsUsageWatch" to change these.
struct ConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "AgentsUsageWatch"
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
