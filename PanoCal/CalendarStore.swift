//
//  CalendarStore.swift
//  PanoCal
//
//  Created by Donald Edwards on 09/11/2026.
//

import SwiftUI
@preconcurrency import EventKit

@MainActor
@Observable
class CalendarStore {
    private let store = EKEventStore()
    var events: [EKEvent] = []
    var calendars: [EKCalendar] = []
    var weekStarts: [Date] = []
    var accessDenied = false
    var remindersDenied = false
    @ObservationIgnored private var currentMonths = 3
    @ObservationIgnored private var currentStart = Date()
    @ObservationIgnored private var currentShowReminders = false
    @ObservationIgnored private var searchCache: [EKEvent]? = nil

    // How far either side of today the search looks, in years.
    private let searchYearsBack = 5
    private let searchYearsAhead = 5

    var hiddenIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? []) {
        didSet {
            UserDefaults.standard.set(Array(hiddenIDs), forKey: "hiddenCalendars")
        }
    }

    var visibleEvents: [EKEvent] {
        events.filter { !hiddenIDs.contains($0.calendar?.calendarIdentifier ?? "") }
    }

    func isVisible(_ calendar: EKCalendar) -> Bool {
        !hiddenIDs.contains(calendar.calendarIdentifier)
    }

    func toggle(_ calendar: EKCalendar) {
        if hiddenIDs.contains(calendar.calendarIdentifier) {
            hiddenIDs.remove(calendar.calendarIdentifier)
        } else {
            hiddenIDs.insert(calendar.calendarIdentifier)
        }
    }

    func showAll() {
        hiddenIDs = []
    }

    func hideAll() {
        hiddenIDs = Set(calendars.map { $0.calendarIdentifier })
    }

    func startObservingChanges() async {
        for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
            searchCache = nil
            store.refreshSourcesIfNecessary()
            await load(start: currentStart, months: currentMonths, showReminders: currentShowReminders)
        }
    }

    // Incomplete reminders that have a due date, turned into stand-in events so every view can draw them.
    private func reminderItems(from start: Date?, to end: Date) async -> [EKEvent] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: nil
        )
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: found ?? [])
            }
        }

        let cal = Calendar.current
        var items: [EKEvent] = []
        for reminder in reminders {
            guard let components = reminder.dueDateComponents,
                  let due = cal.date(from: components) else { continue }

            let hasTime = components.hour != nil
            let item = EKEvent(eventStore: store)
            item.calendar = nil
            item.title = "○ " + (reminder.title ?? "Reminder")
            item.url = URL(string: "panocal-reminder://item")
            item.isAllDay = !hasTime
            item.startDate = hasTime ? due : cal.startOfDay(for: due)
            item.endDate = item.startDate

            var notes = "Reminder"
            if let list = reminder.calendar?.title {
                notes = "Reminder list: " + list
            }
            if let extra = reminder.notes, !extra.isEmpty {
                notes += "\n" + extra
            }
            item.notes = notes
            items.append(item)
        }
        return items
    }

    // Every event in the search span, fetched a year at a time and remembered until the calendar changes.
    func eventsForSearch() async -> [EKEvent] {
        if let cached = searchCache { return cached }

        let cal = Calendar.current
        let now = Date()
        guard let from = cal.date(byAdding: .year, value: -searchYearsBack, to: now),
              let to = cal.date(byAdding: .year, value: searchYearsAhead, to: now) else { return [] }

        var all: [EKEvent] = []
        var seen: Set<String> = []
        var chunkStart = cal.startOfDay(for: from)

        while chunkStart < to {
            let chunkEnd = min(cal.date(byAdding: .year, value: 1, to: chunkStart) ?? to, to)
            let predicate = store.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: nil)

            for event in store.events(matching: predicate) {
                // An event that crosses from one chunk into the next comes back twice, so skip repeats.
                let key = "\(event.eventIdentifier ?? "")-\(event.startDate.timeIntervalSince1970)"
                if seen.insert(key).inserted {
                    all.append(event)
                }
            }

            chunkStart = chunkEnd
            await Task.yield()
            if Task.isCancelled { return all }
        }

        if currentShowReminders && !remindersDenied {
            all += await reminderItems(from: nil, to: to)
        }

        searchCache = all
        return all
    }

    func load(start: Date, months: Int, showReminders: Bool) async {
        if showReminders != currentShowReminders { searchCache = nil }
        currentStart = start
        currentMonths = months
        currentShowReminders = showReminders

        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                accessDenied = true
                return
            }
            if Task.isCancelled { return }

            calendars = store.calendars(for: .event).sorted {
                let a = $0.source?.title ?? ""
                let b = $1.source?.title ?? ""
                return a == b ? $0.title < $1.title : a < b
            }

            let cal = Calendar.current
            let monthStart = cal.dateInterval(of: .month, for: start)?.start ?? start
            let firstWeek = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
            let end = cal.date(byAdding: .month, value: months, to: monthStart) ?? monthStart

            let predicate = store.predicateForEvents(withStart: firstWeek, end: end, calendars: nil)
            var found = store.events(matching: predicate)

            if showReminders {
                let allowed = (try? await store.requestFullAccessToReminders()) ?? false
                remindersDenied = !allowed
                if allowed {
                    found += await reminderItems(from: firstWeek, to: end)
                }
            } else {
                remindersDenied = false
            }
            if Task.isCancelled { return }

            events = found.sorted { $0.startDate < $1.startDate }

            var weeks: [Date] = []
            var current = firstWeek
            while current < end {
                weeks.append(current)
                guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: current) else { break }
                current = next
            }
            weekStarts = weeks
        } catch {
            accessDenied = true
        }
    }
}
