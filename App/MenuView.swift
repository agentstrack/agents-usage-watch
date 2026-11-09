import SwiftUI

/// The panel that opens from the menu bar item.
struct MenuView: View {
    @EnvironmentObject private var store: Store
    @AppStorage("menuChartDays") private var chartDays = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage").font(.system(size: 15, weight: .bold)).tracking(-0.2)
                Spacer()
                if let last = store.lastRefresh {
                    (Text("Updated ") + Text(last, format: .relative(presentation: .named)))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Button { store.refreshNow() } label: {
                    if store.refreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .frame(width: 18)
                .help("Refresh now")
                .keyboardShortcut("r")
            }

            let rows = store.visibleRows
            if rows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.title2).foregroundStyle(.secondary)
                    Text(store.accounts.isEmpty ? "No Claude Code logins found.\nLog in with `claude`, or add a folder in Settings."
                                                : "Fetching usage…")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { t in
                    ScrollView {
                        VStack(spacing: 8) {
                            // Past 4 accounts, tighter cards so more fit before the list scrolls
                            ForEach(rows) { DetailCard(row: $0, now: t.date, compact: rows.count > 4) }
                        }
                    }
                    .frame(maxHeight: 520)
                    .fixedSize(horizontal: false, vertical: true)
                }
                // Spend-only agents (opencode) have no weekly % to chart
                let charted = rows.filter { $0.spend == nil }
                if !charted.isEmpty { progress(charted) }
            }

            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 340)
        .background(OnScreenPanel())
    }

    /// How weekly usage grew: this week or the last 4 weeks, from the app's own history.
    private func progress(_ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("", selection: $chartDays) {
                    Text("Week").tag(7)
                    Text("4 weeks").tag(28)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }
            ProgressChart(rows: rows, series: store.series, days: chartDays, now: .now)
                .frame(height: 110)
            ChartLegend(rows: rows)
        }
    }
}

/// Menu bar managers (Ice, Bartender) hide items by parking them far off-screen, and the panel opens under the
/// item's real position, so it would be invisible. If the panel's window lands off every screen, move it to the
/// top of the screen under the pointer.
private struct OnScreenPanel: NSViewRepresentable {
    final class Probe: NSView {
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // The window is reused between opens and placed by the system each time, so check whenever it's shown
            // or moved (moving it ourselves posts didMove again, but then it's on screen and nothing happens).
            let names: [Notification.Name] = [NSWindow.didMoveNotification, NSWindow.didBecomeKeyNotification,
                                              NSWindow.didChangeOcclusionStateNotification]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated { window.map(Self.pullOnScreen) }
                }
            }
            DispatchQueue.main.async { [weak window] in window.map(Self.pullOnScreen) }
        }

        static func pullOnScreen(_ window: NSWindow) {
            let frame = window.frame
            guard !NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return }
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
            let area = screen.visibleFrame
            let x = min(max(mouse.x - frame.width / 2, area.minX + 8), area.maxX - frame.width - 8)
            // Just below the pointer (i.e. below the manager's bar it was clicked in), bottom kept on screen
            let top = max(min(mouse.y - 16, area.maxY - 4), area.minY + frame.height)
            window.setFrameTopLeftPoint(NSPoint(x: x, y: top))
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}
}
