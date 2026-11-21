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
    let reminders: Bool
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
    @AppStorage("months.overview") private var overviewMonths = 12
    @AppStorage("months.planner") private var plannerMonths = 6
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("viewMode") private var viewMode = "overview"
    @AppStorage("showReminders") private var showReminders = false
    
    // Where each view is navigated to. Remembered only while the app is open.
    @State private var sharedStart = ContentView.currentMonthStart()
    @State private var overviewStart = ContentView.currentMonthStart()
    @State private var plannerStart = ContentView.currentMonthStart()
    @State private var calendarStart = ContentView.currentMonthStart()
    
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
    
    // The first month showing in the current view. With the switch off, all views share one.
    private var startMonth: Date {
        get {
            guard perViewNavigationEnabled else { return sharedStart }
            switch viewMode {
            case "planner": return plannerStart
            case "calendar": return calendarStart
            default: return overviewStart
            }
        }
        nonmutating set {
            guard perViewNavigationEnabled else {
                sharedStart = newValue
                return
            }
            switch viewMode {
            case "planner": plannerStart = newValue
            case "calendar": calendarStart = newValue
            default: overviewStart = newValue
            }
        }
    }
    
    private var syncTitle: String {
        "Set all views to " + startMonth.formatted(.dateTime.month(.abbreviated).year())
    }

    private var viewsInSync: Bool {
        overviewStart == plannerStart && plannerStart == calendarStart
    }

    private func syncAllViews() {
        let current = startMonth
        overviewStart = current
        plannerStart = current
        calendarStart = current
    }

    // The range for whichever view is showing. Calendar is always a single month.
    private var months: Int {
        switch viewMode {
        case "planner": return plannerMonths
        case "calendar": return 1
        default: return overviewMonths
        }
    }

    // Lets the sidebar's range picker change the current view's range.
    private var monthsBinding: Binding<Int> {
        Binding(
            get: { months },
            set: { newValue in
                switch viewMode {
                case "planner": plannerMonths = newValue
                case "calendar": break
                default: overviewMonths = newValue
                }
            }
        )
    }

    private var loadKey: LoadKey {
        LoadKey(months: months, start: startMonth, reminders: showReminders)
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(
                    calendar: calendar,
                    months: monthsBinding,
                    syncTitle: syncTitle,
                    viewsInSync: viewsInSync,
                    onSyncViews: { syncAllViews() }
                )
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
            if !oneMonthEnabled {
                if overviewMonths == 1 { overviewMonths = 3 }
                if plannerMonths == 1 { plannerMonths = 3 }
            }
        }
        .onChange(of: appearance) { _, newValue in
            AppearanceSetting.apply(newValue)
        }
        .onChange(of: selected?.id) { _, newValue in
            if newValue == nil && highlightedDays != nil {
                clearHighlightSoon()
            }
        }
        .task(id: loadKey) {
            await calendar.load(start: startMonth, months: months, showReminders: showReminders)
        }
        .task { await calendar.startObservingChanges() }
        .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { _ in
            exportPDF()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stepMonth)) { note in
            if let step = note.object as? Int {
                shiftMonths(by: step)
            }
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
                    .modifier(SwipeModifier { shiftMonths(by: $0 * months) })
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

            Button {
                exportPDF()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .help("Export as PDF")

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
                shiftMonths(by: -months)
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .help(months == 1 ? "Previous month" : "Previous \(months) months")

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
                shiftMonths(by: months)
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .help(months == 1 ? "Next month" : "Next \(months) months")

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
            GeometryReader { geo in
                let weeks = calendar.weekStarts
                let gap: CGFloat = 4
                let pad: CGFloat = 12
                let count = CGFloat(max(weeks.count, 1))
                let rawH = (geo.size.height - pad * 2 - gap * (count - 1) - 2) / count
                let rowH = rawH.isFinite ? max(80, rawH) : 80

                ScrollView {
                    VStack(spacing: gap) {
                        ForEach(weeks, id: \.self) { weekStart in
                            WeekRow(
                                weekStart: weekStart,
                                events: calendar.visibleEvents,
                                onSelect: { selected = EventItem(event: $0) },
                                onShowDay: { day, events in selectedDay = DayItem(day: day, events: events) },
                                minRowHeight: rowH
                            )
                            .id(weekStart)
                        }
                    }
                    .padding(pad)
                }
                .scrollBounceBehavior(.basedOnSize)
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
            return [AnyView(exportPage {
                GeometryReader { geo in
                    let weeks = calendar.weekStarts
                    let gap: CGFloat = 4
                    let count = CGFloat(max(weeks.count, 1))
                    let rawH = (geo.size.height - 24 - gap * (count - 1)) / count
                    let rowH = rawH.isFinite ? max(60, rawH) : 60

                    VStack(spacing: gap) {
                        ForEach(weeks, id: \.self) { weekStart in
                            WeekRow(
                                weekStart: weekStart,
                                events: calendar.visibleEvents,
                                onSelect: { _ in },
                                onShowDay: { _, _ in },
                                minRowHeight: rowH
                            )
                        }
                    }
                    .padding(12)
                }
            })]
        }
    }
}
