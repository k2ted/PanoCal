//
//  EventDetailView.swift
//  PanoCal
//
//  Created by Donald Edwards on 09/11/2026.
//

import SwiftUI
import EventKit

struct EventItem: Identifiable {
    let id = UUID()
    let event: EKEvent
}

struct EventDetailView: View {
    let event: EKEvent
    @Environment(\.dismiss) private var dismiss

    private var eventColor: Color {
        if let cg = event.calendar?.cgColor {
            return Color(cgColor: cg)
        }
        return .blue
    }

    private var timeText: String {
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start
        let sameDay = Calendar.current.isDate(start, inSameDayAs: end)

        if event.isAllDay {
            let first = start.formatted(date: .complete, time: .omitted)
            if sameDay { return first + "\nAll day" }
            return first + " to\n" + end.formatted(date: .complete, time: .omitted) + "\nAll day"
        }
        if sameDay {
            return start.formatted(date: .complete, time: .omitted) + "\n"
                + start.formatted(date: .omitted, time: .shortened) + " – "
                + end.formatted(date: .omitted, time: .shortened)
        }
        return start.formatted(date: .abbreviated, time: .shortened) + " –\n"
            + end.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                EventDot(event: event, color: eventColor, size: 12)
                Text(event.cleanTitle)
                    .font(.title2.bold())
            }

            Text(timeText)

            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
            }

            if let calendarName = event.calendar?.title {
                Label(calendarName, systemImage: "calendar")
                    .foregroundStyle(.secondary)
            }

            if let notes = event.notes, !notes.isEmpty {
                Text(notes)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 260)
    }
}
