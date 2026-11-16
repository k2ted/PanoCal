//
//  SearchView.swift
//  PanoCal
//
//  Created by Donald Edwards on 11/11/2026.
//

import SwiftUI
import EventKit

struct SearchView: View {
    let calendar: CalendarStore
    let onPick: (EKEvent) -> Void

    @State private var text = ""
    @State private var allEvents: [EKEvent] = []
    @State private var loading = true
    @FocusState private var focused: Bool

    private struct Hit: Identifiable {
        let id: Int
        let event: EKEvent
        var repeatCount: Int
        let note: String?
        let isPast: Bool
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // A short piece of the notes around the matching text.
    private func snippet(of notes: String, around query: String) -> String {
        guard let range = notes.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(notes.prefix(60))
        }
        let start = notes.index(range.lowerBound, offsetBy: -20, limitedBy: notes.startIndex) ?? notes.startIndex
        let end = notes.index(range.upperBound, offsetBy: 40, limitedBy: notes.endIndex) ?? notes.endIndex
        return String(notes[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // Does the event match, and if the match isn't in the title, what text explains it?
    private func match(_ event: EKEvent, _ query: String) -> (found: Bool, note: String?) {
        if (event.title ?? "").localizedCaseInsensitiveContains(query) {
            return (true, nil)
        }
        if let location = event.location, location.localizedCaseInsensitiveContains(query) {
            return (true, "Location: " + location)
        }
        if let notes = event.notes, notes.localizedCaseInsensitiveContains(query) {
            return (true, "Notes: " + snippet(of: notes, around: query))
        }
        return (false, nil)
    }

    // Upcoming events first (soonest first), then past events (most recent first).
    // A repeating event appears once, with a count of how many times it occurs.
    private func makeHits() -> [Hit] {
        let query = trimmed
        guard !query.isEmpty else { return [] }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        var matches: [(event: EKEvent, note: String?)] = []
        for event in allEvents {
            if calendar.hiddenIDs.contains(event.calendar?.calendarIdentifier ?? "") { continue }
            let result = match(event, query)
            if result.found { matches.append((event, result.note)) }
        }

        let upcoming = matches.filter { $0.event.startDate >= startOfToday }
            .sorted { $0.event.startDate < $1.event.startDate }
        let past = matches.filter { $0.event.startDate < startOfToday }
            .sorted { $0.event.startDate > $1.event.startDate }

        var hits: [Hit] = []
        var repeating: [String: Int] = [:]
        for item in upcoming + past {
            if item.event.hasRecurrenceRules, let identifier = item.event.eventIdentifier {
                if let index = repeating[identifier] {
                    hits[index].repeatCount += 1
                    continue
                }
                repeating[identifier] = hits.count
            }
            hits.append(Hit(
                id: hits.count,
                event: item.event,
                repeatCount: 1,
                note: item.note,
                isPast: item.event.startDate < startOfToday
            ))
        }
        return hits
    }

    private func color(for event: EKEvent) -> Color {
        if let cg = event.calendar?.cgColor {
            return Color(cgColor: cg)
        }
        return .blue
    }

    private func dateText(for hit: Hit) -> String {
        let date = hit.event.startDate.formatted(date: .abbreviated, time: hit.event.isAllDay ? .omitted : .shortened)
        return hit.repeatCount > 1 ? "\(date) · repeats, \(hit.repeatCount) times" : date
    }
    
    private func sectionHeader(_ title: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.bold())
                Text("\(count)")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.secondary)
            Divider()
        }
        .padding(.top, 8)
    }

    private func row(_ hit: Hit) -> some View {
        Button {
            onPick(hit.event)
        } label: {
            HStack(spacing: 8) {
                EventDot(event: hit.event, color: color(for: hit.event))
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.event.cleanTitle)
                        .lineLimit(1)
                    if let note = hit.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(dateText(for: hit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let found = makeHits()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search titles, locations and notes", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if loading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading all your events…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if trimmed.isEmpty {
                Text("Searches your visible calendars, five years back and five years ahead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if found.isEmpty {
                Text("No matching events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(found.count > 100
                     ? "Showing the first 100 of \(found.count) matches"
                     : "\(found.count) match\(found.count == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let shown = Array(found.prefix(100))
                let upcoming = shown.filter { !$0.isPast }
                let past = shown.filter { $0.isPast }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if !upcoming.isEmpty {
                            sectionHeader("Upcoming", count: found.filter { !$0.isPast }.count)
                            ForEach(upcoming) { hit in
                                row(hit)
                            }
                        }
                        if !past.isEmpty {
                            sectionHeader("Past", count: found.filter { $0.isPast }.count)
                            ForEach(past) { hit in
                                row(hit)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(width: 380, height: 460)
        .onAppear { focused = true }
        .task {
            allEvents = await calendar.eventsForSearch()
            loading = false
        }
    }
}
