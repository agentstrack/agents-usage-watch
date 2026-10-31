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
                            ForEach(rows) { DetailCard(row: $0, now: t.date) }
                        }
                    }
                    .frame(maxHeight: 520)
                    .fixedSize(horizontal: false, vertical: true)
                }
                progress(rows)
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
                .frame(height: 120)
        }
    }
}
