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
                Text("Drag to reorder. Hidden accounts aren't shown.").font(.caption).foregroundStyle(.secondary)
            }
#if !TESTING
            Text("Set up adds a small helper to the account's Claude Code status line. Claude Code hands it your 5-hour and weekly percentages after each message; the helper saves just those numbers on this Mac and still runs your previous status line, so it looks the same. Your settings.json is backed up first, and Remove puts it back.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
#endif
        }
        .padding()
    }

    /// A CLAUDE_CONFIG_DIR folder outside ~/.claude-*.
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.message = "Choose a Claude Code config folder (the one you set as CLAUDE_CONFIG_DIR)"
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
            Toggle("", isOn: Binding(get: { !account.hidden }, set: { account.hidden = !$0; store.refreshNow() }))
                .labelsHidden().help("Show this account")
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
            if let row { PlanChip(plan: row.plan) }
            status
#if !TESTING
            setup
#endif
            if account.manual {
                Button(role: .destructive) { store.removeAccount(account.id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Remove")
            }
        }
        .padding(.vertical, 2)
        .onDisappear { commit() }
    }

    @ViewBuilder private var status: some View {
        if account.hidden {
            Text("Hidden").font(.caption).foregroundStyle(.secondary)
        } else if let label = row?.status.label {
            Text(label).font(.caption).foregroundStyle(Tone.warn.color)
        } else if row?.status == .ok {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Working")
        }
    }

#if !TESTING
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
                                       : "Read this account's limits from its Claude Code status line"))
    }
#endif

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

    private let levels: [Double] = [50, 60, 70, 75, 80, 85, 90, 95, 99]

    var body: some View {
        Form {
            Toggle("Notifications", isOn: $enabled)
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
                Button("Send Test Notification") {
                    let c = UNMutableNotificationContent()
                    c.title = "AgentsUsageWatch"
                    c.body = "Notifications are working."
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
                }
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
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
            Text("AgentsUsageWatch").font(.title2.bold())
            Text("Version \(Bundle.main.version)").foregroundStyle(.secondary)
#if TESTING
            Text("Testing build: reads each Claude Code login from your Keychain and asks an unofficial usage endpoint for your limits. Not for distribution.")
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
