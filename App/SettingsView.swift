import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AccountsSettings().tabItem { Label("Accounts", systemImage: "person.2") }
            NotificationSettings().tabItem { Label("Notifications", systemImage: "bell.badge") }
            AboutView().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var store: Store
    @AppStorage("refreshInterval") private var interval = 300
#if TESTING
    @AppStorage("wakeExpired") private var wakeExpired = true
#endif
    @AppStorage("menuBarMode") private var menuBarMode = "percent"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Picker("Refresh every", selection: $interval) {
                ForEach(Store.intervals, id: \.self) { s in
                    Text(s < 60 ? "\(s) seconds" : "\(s / 60) minute\(s == 60 ? "" : "s")").tag(s)
                }
            }
            .onChange(of: interval) { store.refreshNow() }
            if interval < 60 {
                Text("Very frequent refreshes can get rate limited by the usage endpoint; the app then backs off on its own.")
                    .font(.caption).foregroundStyle(.secondary)
            }
#if TESTING
            Toggle("Wake expired logins through Claude Code", isOn: $wakeExpired)
            Text("Testing build. Logins expire after ~8 hours without use. The app then runs one tiny Haiku request with that account's Claude Code, which refreshes the login. It never refreshes tokens itself, which would log Claude Code out.")
                .font(.caption).foregroundStyle(.secondary)
#endif
            Picker("Menu bar shows", selection: $menuBarMode) {
                Text("Icon and highest usage").tag("percent")
                Text("Icon only").tag("icon")
            }
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    if launchAtLogin { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }
        }
        .formStyle(.grouped)
    }
}

private struct AccountsSettings: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach($store.accounts) { $account in
                    AccountRowView(account: $account, row: store.rows[account.id])
                }
                .onMove { store.accounts.move(fromOffsets: $0, toOffset: $1); store.writeSnapshot(force: true) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            HStack {
                Button("Add Folder…", action: addFolder)
                Button("Rescan") { store.rescan() }
                Spacer()
                Text("Drag to reorder. Each widget also picks its accounts: right-click it > Edit.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Codex, Antigravity and opencode are detected automatically. Codex limits come from its session logs, opencode shows what it spent, and Antigravity needs Set up (its 3P row covers Claude and GPT-OSS models). Values update while you use each tool.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Set up adds a small helper to the account's Claude Code or Antigravity status line. Claude Code hands it your 5-hour and weekly percentages after each message; the helper saves just those numbers on this Mac and still runs your previous status line, so it looks the same. Your settings.json is backed up first, and Remove puts it back.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    /// A CLAUDE_CONFIG_DIR folder outside ~/.claude-*.
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.message = "Choose a Claude Code config folder (the one you set as CLAUDE_CONFIG_DIR), or ~/.codex for Codex"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { store.addAccount(folder: url) }
    }
}

private struct AccountRowView: View {
    @EnvironmentObject private var store: Store
    @Binding var account: Account
    let row: Row?
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Menu bar", isOn: Binding(get: { account.inMenu }, set: { account.hidden = !$0; store.refreshNow() }))
                    .help("Show in the menu bar panel and notifications")
                Toggle("Widgets", isOn: Binding(get: { account.inWidgets }, set: { account.widgetHidden = !$0; store.refreshNow() }))
                    .help("Offer in the widgets (each widget still picks its accounts: right-click it > Edit)")
            }
            .toggleStyle(.checkbox).controlSize(.small).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                    .onSubmit { commit() }
                    .onAppear { draft = account.name }
                    .onChange(of: account.name) { draft = account.name }
                Text([account.email, (account.id as NSString).abbreviatingWithTildeInPath].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let row, row.spend == nil { PlanChip(plan: row.plan) }
            status
            if account.usesStatusLine { setup }   // testing build too: local values mean fewer endpoint calls
            if account.manual {
                Button(role: .destructive) { store.removeAccount(account.id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Remove")
            }
        }
        .padding(.vertical, 2)
        .onDisappear { commit() }
    }

    @ViewBuilder private var status: some View {
        if !account.inMenu && !account.inWidgets {
            Text("Hidden").font(.caption).foregroundStyle(.secondary)
        } else if let label = row?.status.label {
            Text(label).font(.caption).foregroundStyle(Tone.warn.color)
        } else if row?.status == .ok {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Working")
        }
    }

    @State private var setupError: String?

    @ViewBuilder private var setup: some View {
        let connected = StatusLine.isConnected(account)
        Button(connected ? "Remove" : "Set Up") {
            do {
                if connected { try store.disconnect(account) } else { try store.connect(account) }
                setupError = nil
            } catch {
                setupError = error.localizedDescription
            }
        }
        .controlSize(.small)
        .help(setupError ?? (connected ? "Stop reading this account's status line and restore the previous one"
                                       : "Read this account's limits from its status line"))
    }

    private func commit() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, name != account.name { store.rename(account.id, to: name) } else { draft = account.name }
    }
}

private struct NotificationSettings: View {
    @AppStorage("alertsEnabled") private var enabled = true
    @AppStorage("fiveHourWarn") private var fiveHourWarn = 80.0
    @AppStorage("fiveHourCritical") private var fiveHourCritical = 95.0
    @AppStorage("weeklyWarn") private var weeklyWarn = 80.0
    @AppStorage("weeklyCritical") private var weeklyCritical = 95.0
    @AppStorage("alertRunOut") private var runOut = true
    @AppStorage("alertForecast") private var forecast = true
    @AppStorage("alertBurnRate") private var burnRate = true
    @AppStorage("quietHours") private var quiet = true
    @AppStorage("quietFrom") private var quietFrom = 23
    @AppStorage("quietTo") private var quietTo = 8

    @AppStorage(Notifications.soundOnKey) private var soundOn = true
    @AppStorage(Notifications.soundKey) private var sound = "default"
    @State private var permission: UNNotificationSettings?
    @State private var testResult: String?

    private let levels: [Double] = [50, 60, 70, 75, 80, 85, 90, 95, 99]

    var body: some View {
        Form {
            Section {
                Toggle("Notifications", isOn: $enabled)
                LabeledContent("macOS permission") { permissionStatus }
                Toggle("Play a sound", isOn: $soundOn)
                if soundOn {
                    Picker("Sound", selection: $sound) {
                        Text("System default").tag("default")
                        Divider()
                        ForEach(Notifications.soundNames, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: sound) { _, name in Notifications.preview(name) }
                }
                if soundOn, permission?.soundSetting == .disabled {
                    Text("Sounds are off for Agents Usage Watch in System Settings › Notifications, so none will play.")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Send Test Notification") { Task { await sendTest() } }
                    if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Group {
                Section("Thresholds (once per window)") {
                    thresholds("5-hour window", $fiveHourWarn, $fiveHourCritical)
                    thresholds("Weekly window", $weeklyWarn, $weeklyCritical)
                }
                Section("Forecasts") {
                    Toggle("May run out before the weekly reset", isOn: $runOut)
                    Toggle("Mid-week: on track to leave a lot unused", isOn: $forecast)
                    Toggle("Burning much faster than usual", isOn: $burnRate)
                    Text("Compares the last hour with your usual active hour over the past week; needs a few days of history first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Quiet hours") {
                    Toggle("Hold notifications at night", isOn: $quiet)
                    if quiet {
                        LabeledContent("From") {
                            HStack(spacing: 6) {
                                Picker("From", selection: $quietFrom) { hours }.labelsHidden().fixedSize()
                                Text("to").foregroundStyle(.secondary)
                                Picker("To", selection: $quietTo) { hours }.labelsHidden().fixedSize()
                            }
                        }
                        Text("Anything still true afterwards is sent when quiet hours end.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
        .task { await readPermission() }
        // The user may have just changed it in System Settings
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await readPermission() }
        }
    }

    @ViewBuilder private var permissionStatus: some View {
        switch permission?.authorizationStatus {
        case nil:
            ProgressView().controlSize(.small)
        case .notDetermined?:
            Button("Allow Notifications…") {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    await readPermission()
                }
            }
        case let status? where Notifications.allowed(status):
            if permission?.alertStyle == UNAlertStyle.none {
                // Allowed, but they only land in Notification Centre
                HStack(spacing: 6) {
                    Label("Banners off", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Link("Change…", destination: Notifications.settingsURL)
                }
            } else {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        default:
            HStack(spacing: 6) {
                Label("Off", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                Link("Open System Settings…", destination: Notifications.settingsURL)
            }
        }
    }

    private func readPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings()
    }

    /// Asks for permission if never asked, then says what happened instead of failing silently.
    private func sendTest() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        await readPermission()
        guard let permission, Notifications.allowed(permission.authorizationStatus) else {
            testResult = "Not sent: notifications are off for this app."
            return
        }
        do {
            try await center.add(Notifications.request(id: UUID().uuidString, title: "Agents Usage Watch",
                                                       body: "Notifications are working."))
            testResult = permission.alertStyle == UNAlertStyle.none
                ? "Sent to Notification Centre (banners are off)."
                : "Sent. In a Focus it only shows if that Focus allows Agents Usage Watch."
        } catch {
            testResult = "Not sent: \(error.localizedDescription)"
        }
    }

    /// "5-hour window   warn [80%] · alert [95%]"
    private func thresholds(_ title: String, _ warn: Binding<Double>, _ critical: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Picker("Warn at", selection: warn) { levelTags }.labelsHidden().fixedSize()
                Text("and").foregroundStyle(.secondary)
                Picker("Alert at", selection: critical) { levelTags }.labelsHidden().fixedSize()
            }
        }
    }

    private var levelTags: some View {
        ForEach(levels, id: \.self) { Text("\(Int($0))%").tag($0) }
    }

    private var hours: some View {
        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Agents Usage Watch").font(.title2.bold())
            Text("Version \(Bundle.main.version)").foregroundStyle(.secondary)
#if TESTING
            Text("Testing build: uses Claude Code's status line when it is fresh, otherwise reads the login from your Keychain and asks an unofficial usage endpoint (at most once per 5 minutes per account). Not for distribution.")
                .font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center).frame(maxWidth: 380)
#else
            Text("Shows the plan limits your coding agents report, on this Mac. Claude limits come from Claude Code's own status line, so they update while you use Claude Code. Nothing is sent anywhere. Not affiliated with Anthropic.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
#endif
            Link("A free tool from AgentsTrack", destination: URL(string: "https://agentstrack.ai")!).font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
