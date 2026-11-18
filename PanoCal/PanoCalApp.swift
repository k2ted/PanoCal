//
//  PanoCalApp.swift
//  PanoCal
//
//  Created by Donald Edwards on 09/11/2026.
//

import SwiftUI

@main
struct PanoCalApp: App {
    @AppStorage("viewMode") private var viewMode = "overview"
    @AppStorage("months.overview") private var overviewMonths = 12
    @AppStorage("months.planner") private var plannerMonths = 6
    @AppStorage("showEventTimes") private var showTimes = false

    // Calendar is always a single month, so the range shortcuts do nothing there.
    private func setMonths(_ value: Int) {
        switch viewMode {
        case "planner": plannerMonths = value
        case "calendar": break
        default: overviewMonths = value
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .importExport) {
                Button("Export as PDF…") {
                    NotificationCenter.default.post(name: .exportRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandMenu("Display") {
                if oneMonthEnabled {
                    Button("1 Month") { setMonths(1) }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("3 Months") { setMonths(3) }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("6 Months") { setMonths(6) }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("12 Months") { setMonths(12) }
                        .keyboardShortcut("4", modifiers: .command)
                } else {
                    Button("3 Months") { setMonths(3) }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("6 Months") { setMonths(6) }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("12 Months") { setMonths(12) }
                        .keyboardShortcut("3", modifiers: .command)
                }

                Divider()

                Toggle("Show Event Times", isOn: $showTimes)
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}
