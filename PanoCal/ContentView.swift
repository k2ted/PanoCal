//
//  ContentView.swift
//  PanoCal
//
//  Created by Donald Edwards on 09/11/2026.
//

import SwiftUI
import EventKit
import UniformTypeIdentifiers

private struct LoadKey: Hashable {
    let months: Int
    let start: Date
}

// Lets a left or right swipe change the month on touch screens. Does nothing on Mac.
private struct SwipeModifier: ViewModifier {
    let onSwipe: (Int) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content.simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > 80 && abs(dx) > abs(dy) * 2 {
                        onSwipe(dx < 0 ? 1 : -1)
                    }
                }
        )
        #else
        content
        #endif
    }
}

struct ContentView: View {
    @State private var calendar = CalendarStore()
    @AppStorage("selectedMonths") private var months = 12
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("viewMode") private var viewMode = "overview"
    @State private var startMonth = ContentView.currentMonthStart()
    @State private var showSidebar = false
    @State private var showSearch = false
    @State private var showJump = false
    @State private var selected: EventItem?
    @State private var selectedDay: DayItem?
    @State private var highlightedDays: ClosedRange<Date>?
    @State private var highlightToken = UUID()
    @State private var exportFile: PDFFile?
    @State private var showExporter = false

    private static func currentMonthStart() -> Date {
        Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    private var loadKey: LoadKey {
        LoadKey(months: months, start: startMonth)
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(calendar: calendar, months: $months)
                    .frame(width: 280)
                    .transition(.move(edge: .leading))
                Divider()
            }
            mainContent
        }
        .animation(.easeInOut(duration: 0.2), value: showSidebar)
        .environment(\.highlightedDays, highlightedDays)
        .onAppear {
            AppearanceSetting.apply(appearance)
            if months == 1 && !oneMonthEnabled { months = 3 }
        }
        .onChange(of: appearance) { _, newValue in
            AppearanceSetting.apply(newValue)
        }
        .onChange(of: selected?.id) { _, newValue in
            if newValue == nil && highlightedDays != nil {
                clearHighlightSoon()
            }
        }
        .task(id: loadKey) { await calendar.load(start: startMonth, months: months) }
        .task { await calendar.startObservingChanges() }
        .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { _ in
            exportPDF()
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportFile ?? PDFFile(data: Data()),
            contentType: .pdf,
            defaultFilename: "PanoCal \(rangeTitle)"
        ) { _ in }
        .sheet(item: $selected) { item in
            EventDetailView(event: item.event)
        }
        .sheet(item: $selectedDay) { item in
            DayListView(day: item.day, events: item.events)
        }
    }

    // The text on the button that opens the month and year selector.
    private var rangeTitle: String {
        let cal = Calendar.current
        let style = Date.FormatStyle().month(.abbreviated).year()
        guard months > 1,
              let last = cal.date(byAdding: .month, value: months - 1, to: startMonth) else {
            return startMonth.formatted(.dateTime.month(.wide).year())
        }
        return "\(startMonth.formatted(style)) – \(last.formatted(style))"
    }

    private var mainContent: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                topBar(proxy)
                contentArea
                    .modifier(SwipeModifier { shiftMonths(by: $0) })
            }
            .onChange(of: calendar.weekStarts.first) { _, newFirst in
                if let newFirst {
                    proxy.scrollTo(newFirst, anchor: .top)
                }
            }
        }
    }

    private func topBar(_ proxy: ScrollViewProxy) -> some View {
        HStack {
            Button {
                showSidebar.toggle()
            } label: {
                Label("Sidebar", systemImage: "sidebar.left")
                    .labelStyle(.iconOnly)
            }
            .help("Show or hide the sidebar")
            .keyboardShortcut("s", modifiers: [.command, .control])

            Spacer()

            Button {
                showSearch.toggle()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("f", modifiers: .command)
            .help("Search events")
            .popover(isPresented: $showSearch) {
                SearchView(calendar: calendar) { event in
                    showSearch = false
                    pick(event)
                }
            }
            
            Button {
                exportPDF()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .help("Export as PDF")

            Button {
                shiftMonths(by: -1)
            } label: {
                Label("Previous month", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .help("Previous month")

            Button {
                showJump.toggle()
            } label: {
                Text(rangeTitle)
            }
            .fixedSize()
            .help("Choose a month and year")
            .popover(isPresented: $showJump) {
                JumpToMonthView(
                    current: startMonth,
                    onConfirm: { date in
                        startMonth = date
                        showJump = false
                    },
                    onCancel: { showJump = false }
                )
            }

            Button {
                shiftMonths(by: 1)
            } label: {
                Label("Next month", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .help("Next month")

            Button("Today") {
                goToCurrentMonth(proxy)
            }
            .keyboardShortcut("t", modifiers: .command)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .padding()
    }

    @ViewBuilder
    private var contentArea: some View {
        if calendar.accessDenied {
            Text("Calendar access was denied. You can allow it in System Settings > Privacy & Security > Calendars.")
                .padding()
        } else if viewMode == "overview" {
            OverviewView(
                calendar: calendar,
                months: months,
                startMonth: startMonth,
                onSelect: { selected = EventItem(event: $0) },
                onShowDay: { day, events in selectedDay = DayItem(day: day, events: events) }
            )
            .id(loadKey)
        } else if viewMode == "planner" {
            PlannerView(
                calendar: calendar,
                months: months,
                startMonth: startMonth,
                onSelect: { selected = EventItem(event: $0) },
                onShowDay: { day, events in selectedDay = DayItem(day: day, events: events) }
            )
            .id(loadKey)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(calendar.weekStarts.enumerated()), id: \.element) { index, weekStart in
                        VStack(spacing: 4) {
                            if let label = monthLabel(for: weekStart, index: index) {
                                Text(label)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }
                            WeekRow(
                                weekStart: weekStart,
                                events: calendar.visibleEvents,
                                onSelect: { selected = EventItem(event: $0) },
                                onShowDay: { day, events in selectedDay = DayItem(day: day, events: events) }
                            )
                        }
                        .id(weekStart)
                    }
                }
                .padding()
            }
        }
    }
    
    @MainActor
    private func exportPDF() {
        guard let data = PDFExport.makePDF(pages: exportPages()) else { return }
        exportFile = PDFFile(data: data)
        showExporter = true
    }

    // A page with a small heading above whatever view is being exported.
    @MainActor
    private func exportPage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("PanoCal")
                    .font(.headline)
                Text(rangeTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            content()
        }
    }

    @MainActor
    private func exportPages() -> [AnyView] {
        switch viewMode {
        case "overview":
            return [AnyView(exportPage {
                OverviewView(
                    calendar: calendar,
                    months: months,
                    startMonth: startMonth,
                    onSelect: { _ in },
                    onShowDay: { _, _ in }
                )
            })]
        case "planner":
            return [AnyView(exportPage {
                PlannerView(
                    calendar: calendar,
                    months: months,
                    startMonth: startMonth,
                    onSelect: { _ in },
                    onShowDay: { _, _ in },
                    forExport: true
                )
            })]
        default:
            let weeks = calendar.weekStarts
            let events = calendar.visibleEvents
            let perPage = 6
            let chunks = stride(from: 0, to: weeks.count, by: perPage).map {
                Array(weeks[$0..<min($0 + perPage, weeks.count)])
            }
            return chunks.enumerated().map { pageIndex, chunk in
                AnyView(exportPage {
                    VStack(spacing: 4) {
                        ForEach(Array(chunk.enumerated()), id: \.element) { i, weekStart in
                            if let label = monthLabel(for: weekStart, index: pageIndex * perPage + i) {
                                Text(label)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }
                            WeekRow(
                                weekStart: weekStart,
                                events: events,
                                onSelect: { _ in },
                                onShowDay: { _, _ in }
                            )
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                })
            }
        }
    }

    private func shiftMonths(by value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: startMonth) {
            startMonth = next
        }
    }

    private func goToCurrentMonth(_ proxy: ScrollViewProxy) {
        let current = ContentView.currentMonthStart()
        if startMonth == current {
            if let first = calendar.weekStarts.first {
                withAnimation {
                    proxy.scrollTo(first, anchor: .top)
                }
            }
        } else {
            startMonth = current
        }
    }

    private func pick(_ event: EKEvent) {
        if let start = event.startDate {
            let cal = Calendar.current
            let end = event.endDate ?? start
            let lastMoment = end > start ? end.addingTimeInterval(-1) : start
            let firstDay = cal.startOfDay(for: start)
            let lastDay = max(cal.startOfDay(for: lastMoment), firstDay)

            highlightedDays = firstDay...lastDay
            highlightToken = UUID()

            // Make the event's month the first month of the range.
            if let monthStart = cal.dateInterval(of: .month, for: start)?.start {
                startMonth = monthStart
            }
        }
        // A short pause lets the search panel close before the details panel opens.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            selected = EventItem(event: event)
        }
    }

    private func clearHighlightSoon() {
        let token = highlightToken
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if token == highlightToken {
                withAnimation { highlightedDays = nil }
            }
        }
    }

    private func monthLabel(for weekStart: Date, index: Int) -> String? {
        let cal = Calendar.current
        for offset in 0..<7 {
            let day = cal.date(byAdding: .day, value: offset, to: weekStart)!
            if cal.component(.day, from: day) == 1 {
                return day.formatted(.dateTime.month(.wide).year())
            }
        }
        if index == 0 {
            return weekStart.formatted(.dateTime.month(.wide).year())
        }
        return nil
    }
}
