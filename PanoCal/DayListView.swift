//
//  DayListView.swift
//  PanoCal
//
//  Created by Donald Edwards on 09/11/2026.
//

import SwiftUI
import EventKit

struct DayItem: Identifiable {
    let id = UUID()
    let day: Date
    let events: [EKEvent]
}

struct DayListView: View {
    let day: Date
    let events: [EKEvent]
    @Environment(\.dismiss) private var dismiss

    private func color(for event: EKEvent) -> Color {
        if let cg = event.calendar?.cgColor {
            return Color(cgColor: cg)
        }
        return .blue
    }

    private func timeText(for event: EKEvent) -> String {
        if event.isAllDay { return "All day" }
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start
        return start.formatted(date: .omitted, time: .shortened)
            + " – " + end.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            List(Array(events.enumerated()), id: \.offset) { item in
                NavigationLink {
                    EventDetailView(event: item.element)
                } label: {
                    HStack(spacing: 8) {
                        EventDot(event: item.element, color: color(for: item.element))
                        VStack(alignment: .leading) {
                            Text(item.element.cleanTitle)
                                .lineLimit(1)
                            Text(timeText(for: item.element))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView("No events", systemImage: "calendar")
                }
            }
            .navigationTitle(day.formatted(date: .complete, time: .omitted))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 400)
    }
}
