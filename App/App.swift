import ServiceManagement
import SwiftUI
import UserNotifications

// Menu bar app: reads plan limits for every Claude Code login, shows them in the menu bar panel,
// writes the widget's snapshot and posts alerts.
@main struct AgentsUsageWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView().environmentObject(store) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // Start at login by default (once; the user can turn it off in Settings)
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
        }
        Task { @MainActor in Store.shared.start() }
    }

    /// Without this macOS drops notifications while the app is frontmost, e.g. with Settings open (the test button).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// agentsusagewatch://refresh — tapping the widget opens this URL.
    /// agentsusagewatch://settings — the widget's "Set up in Settings" note opens the Settings window.
    func application(_ application: NSApplication, open urls: [URL]) {
        log.info("opened by URL")
        if urls.contains(where: { $0.host == "settings" }) {
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                SettingsOpener.open?()
            }
            return
        }
        Task { @MainActor in Store.shared.refreshNow() }
    }
}

/// Menu bar item: a gauge, plus the highest usage among visible accounts unless set to icon only.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: Store
    @AppStorage("menuBarMode") private var mode = "percent"
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let top = store.visibleRows.compactMap { r in [r.h5, r.d7].compactMap { $0 }.max() }.max()
        Group {
            if mode == "percent", let top {
                Label("\(Int(top.rounded()))%", systemImage: icon(top)).labelStyle(.titleAndIcon)
            } else {
                Image(systemName: icon(top ?? 0))
            }
        }
        // The label lives as long as the app, so it lends its openSettings to code outside SwiftUI
        .onAppear { SettingsOpener.open = { openSettings() } }
    }

    private func icon(_ pct: Double) -> String {
        pct >= 67 ? "gauge.with.dots.needle.67percent" : pct >= 33 ? "gauge.with.dots.needle.50percent" : "gauge.with.dots.needle.33percent"
    }
}

/// macOS 14+ ignores showSettingsWindow: for SwiftUI apps ("Please use SettingsLink"), so URL handlers
/// open Settings through SwiftUI's openSettings, handed over by MenuBarLabel.
@MainActor enum SettingsOpener {
    static var open: (() -> Void)?
}
