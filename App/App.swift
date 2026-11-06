import ServiceManagement
import SwiftUI

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start at login by default (once; the user can turn it off in Settings)
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
        }
        Task { @MainActor in Store.shared.start() }
    }

    /// agentsusagewatch://refresh — tapping the widget opens this URL.
    /// agentsusagewatch://settings — the widget's "Set up in Settings" note opens the Settings window.
    func application(_ application: NSApplication, open urls: [URL]) {
        log.info("opened by URL")
        if urls.contains(where: { $0.host == "settings" }) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            return
        }
        Task { @MainActor in Store.shared.refreshNow() }
    }
}

/// Menu bar item: a gauge, plus the highest usage among visible accounts unless set to icon only.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: Store
    @AppStorage("menuBarMode") private var mode = "percent"

    var body: some View {
        let top = store.visibleRows.compactMap { r in [r.h5, r.d7].compactMap { $0 }.max() }.max()
        if mode == "percent", let top {
            Label("\(Int(top.rounded()))%", systemImage: icon(top)).labelStyle(.titleAndIcon)
        } else {
            Image(systemName: icon(top ?? 0))
        }
    }

    private func icon(_ pct: Double) -> String {
        pct >= 67 ? "gauge.with.dots.needle.67percent" : pct >= 33 ? "gauge.with.dots.needle.50percent" : "gauge.with.dots.needle.33percent"
    }
}
