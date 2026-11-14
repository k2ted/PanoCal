//
//  PlannerView.swift
//  PanoCal
//
//  Created by Donald Edwards on 11/11/2026.
//

import SwiftUI
import EventKit

private enum PlannerMetrics {
    static let laneWidth: CGFloat = 12
    static let laneGap: CGFloat = 2
    static let labelWidth: CGFloat = 25
    static let laneStartX: CGFloat = 31    // cell padding 3 + label 25 + spacing 3
}

private func plannerColor(for event: EKEvent) -> Color {
    if let cg = event.calendar?.cgColor {
        return Color(cgColor: cg)
    }
    return .blue
}

private func plannerSorted(_ list: [EKEvent]) -> [EKEvent] {
    list.sorted { a, b in
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        return a.startDate < b.startDate
    }
}

struct PlannerView: View {
    let calendar: CalendarStore
    let months: Int
    let startMonth: Date
    let onSelect: (EKEvent) -> Void
    let onShowDay: (Date, [EKEvent]) -> Void
    
    var forExport = false   // set when drawing a PDF, which can't render scrolling views

    private struct PlannerBar {
        let event: EKEvent
        let startRow: Int
        let endRow: Int
        let lane: Int
        let before: Bool
        let after: Bool
    }

    private struct ColumnLayout {
        var bars: [PlannerBar] = []
        var laneCount = 0
        var lanedIndexes: Set<Int> = []
        var lanesUsedByRow: [Int] = Array(repeating: 0, count: 31)
    }

    private var monthStarts: [Date] {
        let cal = Calendar.current
        let first = cal.dateInterval(of: .month, for: startMonth)?.start ?? startMonth
        return (0..<months).compactMap { cal.date(byAdding: .month, value: $0, to: first) }
    }

    // Groups the events by the day(s) they fall on. Stores positions in the events array, not the events themselves.
    private func eventsByDay(events: [EKEvent], rangeStart: Date, rangeEnd: Date) -> [Date: [Int]] {
        let cal = Calendar.current
        var result: [Date: [Int]] = [:]
        guard let lastAllowed = cal.date(byAdding: .day, value: -1, to: rangeEnd) else { return result }

        for (index, event) in events.enumerated() {
            guard let start = event.startDate, let end = event.endDate else { continue }
            let lastMoment = end > start ? end.addingTimeInterval(-1) : start
            var day = max(cal.startOfDay(for: start), rangeStart)
            let lastDay = min(cal.startOfDay(for: lastMoment), lastAllowed)

            while day <= lastDay {
                result[day, default: []].append(index)
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result
    }

    // Works out which multi-day events become vertical bars in this month, and which lane each sits in.
    private func makeColumnLayout(events: [EKEvent], monthStart: Date, dayCount: Int, maxLanes: Int) -> ColumnLayout {
        let cal = Calendar.current
        var result = ColumnLayout()

        struct Span {
            let index: Int
            let event: EKEvent
            let startRow: Int
            let endRow: Int
            let before: Bool
            let after: Bool
        }
        var spans: [Span] = []

        for (index, event) in events.enumerated() {
            guard let start = event.startDate, let end = event.endDate else { continue }
            let lastMoment = end > start ? end.addingTimeInterval(-1) : start
            let firstDay = cal.startOfDay(for: start)
            let lastDay = cal.startOfDay(for: lastMoment)
            guard lastDay > firstDay else { continue }   // single-day events stay as chips

            let rawStart = cal.dateComponents([.day], from: monthStart, to: firstDay).day ?? 0
            let rawEnd = cal.dateComponents([.day], from: monthStart, to: lastDay).day ?? 0
            if rawEnd < 0 || rawStart > dayCount - 1 { continue }

            spans.append(Span(
                index: index,
                event: event,
                startRow: max(rawStart, 0),
                endRow: min(rawEnd, dayCount - 1),
                before: rawStart < 0,
                after: rawEnd > dayCount - 1
            ))
        }

        spans.sort {
            if $0.startRow != $1.startRow { return $0.startRow < $1.startRow }
            return ($0.endRow - $0.startRow) > ($1.endRow - $1.startRow)
        }

        var laneEnds: [Int] = []
        for span in spans {
            var lane = -1
            for i in 0..<laneEnds.count where laneEnds[i] < span.startRow {
                lane = i
                break
            }
            if lane == -1 {
                if laneEnds.count >= maxLanes { continue }
                laneEnds.append(span.endRow)
                lane = laneEnds.count - 1
            } else {
                laneEnds[lane] = span.endRow
            }
            result.bars.append(PlannerBar(
                event: span.event,
                startRow: span.startRow,
                endRow: span.endRow,
                lane: lane,
                before: span.before,
                after: span.after
            ))
            result.lanedIndexes.insert(span.index)
            for row in span.startRow...span.endRow {
                result.lanesUsedByRow[row] = max(result.lanesUsedByRow[row], lane + 1)
            }
        }
        result.laneCount = laneEnds.count
        return result
    }

    var body: some View {
        let events = calendar.visibleEvents      // one snapshot, used for everything below
        let starts = monthStarts
        let rangeStart = starts.first ?? Date()
        let rangeEnd = Calendar.current.date(byAdding: .month, value: months, to: rangeStart) ?? rangeStart
        let byDay = eventsByDay(events: events, rangeStart: rangeStart, rangeEnd: rangeEnd)

        GeometryReader { geo in
            let spacing: CGFloat = 4
            let outerPad: CGFloat = 12
            let headerH: CGFloat = 24
            let rowGap: CGFloat = 2
            let count = CGFloat(max(starts.count, 1))
            let colW = (geo.size.width - outerPad * 2 - spacing * (count - 1)) / count
            let rowH = max(18, (geo.size.height - outerPad * 2 - headerH - rowGap * 31) / 31)

            let columns = HStack(alignment: .top, spacing: spacing) {
                ForEach(starts, id: \.self) { monthStart in
                    monthColumn(monthStart, events: events, byDay: byDay, colW: colW,
                                rowH: rowH, headerH: headerH, rowGap: rowGap)
                }
            }
            .padding(outerPad)

            if forExport {
                columns
            } else {
                ScrollView(.vertical) {
                    columns
                }
            }
        }
    }

    private func monthColumn(_ monthStart: Date, events: [EKEvent], byDay: [Date: [Int]],
                             colW: CGFloat, rowH: CGFloat, headerH: CGFloat, rowGap: CGFloat) -> some View {
        let cal = Calendar.current
        let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let layout = makeColumnLayout(events: events, monthStart: monthStart, dayCount: dayCount,
                                      maxLanes: colW > 500 ? 5 : (colW > 180 ? 3 : 2))

        return VStack(spacing: rowGap) {
            Text(monthStart.formatted(.dateTime.month(.abbreviated).year()))
                .font(.caption.bold())
                .frame(maxWidth: .infinity, minHeight: headerH, maxHeight: headerH)

            ForEach(0..<31, id: \.self) { i in
                if i < dayCount, let date = cal.date(byAdding: .day, value: i, to: monthStart) {
                    let indexes = byDay[cal.startOfDay(for: date)] ?? []
                    let all = plannerSorted(indexes.map { events[$0] })
                    let chips = plannerSorted(
                        indexes.filter { !layout.lanedIndexes.contains($0) }.map { events[$0] }
                    )
                    let reserve = CGFloat(layout.lanesUsedByRow[i]) * (PlannerMetrics.laneWidth + PlannerMetrics.laneGap)

                    PlannerDayCell(
                        date: date,
                        chips: chips,
                        allEvents: all,
                        width: colW,
                        height: rowH,
                        reserve: reserve,
                        onSelect: onSelect,
                        onShowDay: onShowDay
                    )
                } else {
                    Color.clear.frame(height: rowH)
                }
            }
        }
        .frame(width: colW)
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.bars.enumerated()), id: \.offset) { _, bar in
                    let x = PlannerMetrics.laneStartX
                        + CGFloat(bar.lane) * (PlannerMetrics.laneWidth + PlannerMetrics.laneGap)
                    let y = headerH + rowGap + CGFloat(bar.startRow) * (rowH + rowGap) + 1

                    barView(bar, rowH: rowH, rowGap: rowGap)
                        .offset(x: x, y: y)
                }
            }
        }
    }

    private func barView(_ bar: PlannerBar, rowH: CGFloat, rowGap: CGFloat) -> some View {
        let rows = CGFloat(bar.endRow - bar.startRow + 1)
        let height = max(rows * rowH + (rows - 1) * rowGap - 2, 0)
        let color = plannerColor(for: bar.event)
        let r: CGFloat = 4
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: bar.before ? 0 : r,
            bottomLeadingRadius: bar.after ? 0 : r,
            bottomTrailingRadius: bar.after ? 0 : r,
            topTrailingRadius: bar.before ? 0 : r
        )

        return Text(bar.event.title ?? "Untitled")
            .font(.system(size: 8, weight: .medium))
            .lineLimit(1)
            .frame(width: max(height - 6, 0), height: PlannerMetrics.laneWidth, alignment: .leading)
            .rotationEffect(.degrees(90))
            .frame(width: PlannerMetrics.laneWidth, height: height)
            .background(color.opacity(0.4))
            .overlay(alignment: .top) {
                if !bar.before {
                    Rectangle()
                        .fill(color)
                        .frame(height: 2)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { onSelect(bar.event) }
    }
}

struct PlannerDayCell: View {
    let date: Date
    let chips: [EKEvent]
    let allEvents: [EKEvent]
    let width: CGFloat
    let height: CGFloat
    let reserve: CGFloat
    let onSelect: (EKEvent) -> Void
    let onShowDay: (Date, [EKEvent]) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showEventTimes") private var showTimes = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var isWeekend: Bool {
        Calendar.current.isDateInWeekend(date)
    }
    
    @Environment(\.highlightedDays) private var highlightedDays

    private var isHighlighted: Bool {
        guard let highlightedDays else { return false }
        return highlightedDays.contains(Calendar.current.startOfDay(for: date))
    }

    private var maxChips: Int {
        let eventWidth = width - 35 - reserve
        let cap = width > 500 ? 6 : 3
        let perChip: CGFloat = showTimes ? 85 : 60
        return min(cap, max(1, Int(eventWidth / perChip)))
    }
    
    private var cellBackground: Color {
        if isHighlighted { return Color.accentColor.opacity(0.25) }
        if isToday { return Color.red.opacity(0.12) }
        if isWeekend { return Color.gray.opacity(colorScheme == .dark ? 0.30 : 0.20) }
        return Color.gray.opacity(colorScheme == .dark ? 0.14 : 0.07)
    }
    
    private func label(for event: EKEvent) -> String {
        let title = event.title ?? "Untitled"
        guard showTimes,
              !event.isAllDay,
              Calendar.current.isDate(event.startDate, inSameDayAs: date) else {
            return title
        }
        let time = event.startDate.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        return "\(time) \(title)"
    }

    private func chip(_ event: EKEvent) -> some View {
        let color = plannerColor(for: event)
        return Text(label(for: event))
            .font(.system(size: 9))
            .lineLimit(1)
            .padding(.leading, 5)
            .padding(.trailing, 2)
            .frame(maxWidth: width > 300 ? CGFloat(180) : CGFloat.infinity, alignment: .leading)
            .frame(height: min(height - 6, 18))
            .background(color.opacity(0.3))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .onTapGesture { onSelect(event) }
    }

    var body: some View {
        let shown = Array(chips.prefix(maxChips))
        let overflow = chips.count - shown.count

        HStack(spacing: 3) {
            HStack(spacing: 1) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 10, weight: .bold))
                    .fixedSize()
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .frame(width: PlannerMetrics.labelWidth, alignment: .leading)
            .frame(width: PlannerMetrics.labelWidth, alignment: .leading)

            if reserve > 0 {
                Color.clear
                    .frame(width: reserve, height: 1)
            }

            ForEach(Array(shown.enumerated()), id: \.offset) { item in
                chip(item.element)
            }

            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.blue)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(height: height)
        .background(cellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isHighlighted ? Color.accentColor : (isToday ? Color.red : Color.clear), lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.25), value: isHighlighted)
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .onTapGesture { onShowDay(date, allEvents) }
    }
}
