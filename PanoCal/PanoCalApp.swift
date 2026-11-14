//
//  PanoCalApp.swift
//  PanoCal
//
//  Created by Donald Edwards on 09/11/2026.
//

import SwiftUI

@main
struct PanoCalApp: App {
    @AppStorage("selectedMonths") private var months = 12
    @AppStorage("showEventTimes") private var showTimes = false

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandMenu("Display") {
                if oneMonthEnabled {
                    Button("1 Month") { months = 1 }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("3 Months") { months = 3 }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("6 Months") { months = 6 }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("12 Months") { months = 12 }
                        .keyboardShortcut("4", modifiers: .command)
                } else {
                    Button("3 Months") { months = 3 }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("6 Months") { months = 6 }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("12 Months") { months = 12 }
                        .keyboardShortcut("3", modifiers: .command)
                }

                Divider()

                Toggle("Show Event Times", isOn: $showTimes)
                    .keyboardShortcut("e", modifiers: .command)
            }
            
            CommandGroup(replacing: .importExport) {
                Button("Export as PDF…") {
                    NotificationCenter.default.post(name: .exportRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}
