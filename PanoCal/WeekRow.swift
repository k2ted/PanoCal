//
//  WeekRow.swift
//  PanoCal
//
//  Created by Donald Edwards on 09/11/2026.
//

import SwiftUI
import EventKit

enum WeekMetrics {
    static let columnSpacing: CGFloat = 4
    static let cellPadding: CGFloat = 4
    static let cellSpacing: CGFloat = 2
    static let headerHeight: CGFloat = 18
    static let laneHeight: CGFloat = 16
    static let laneGap: CGFloat = 2
    static let maxLanes = 3
    static let maxRows = 3
}

private func calendarColor(for event: EKEvent) -> Color {
    if let cg = event.calendar?.cgColor {
        return Color(cgColor: cg)
    }
    return .blue
}

private func sortedForDay(_ list: [EKEvent]) -> [EKEvent] {
    list.sorted { a, b in
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        return a.startDate < b.startDate
    }
}

struct WeekRow: View {
    let weekStart: Date
    let events: [EKEvent]
    let onSelect: (EKEvent) -> Void
    let onShowDay: (Date, [EKEvent]) -> Void
    var minRowHeight: CGFloat = 80

    private struct Bar {
        let event: EKEvent
        let startCol: Int
        let endCol: Int
        let lane: Int
        let continuesBefore: Bool
        let continuesAfter: Bool
    }

    private struct WeekLayout {
        var bars: [Bar] = []
        var laneCount = 0
        var allByDay: [[EKEvent]] = Array(repeating: [], count: 7)
        var singlesByDay: [[EKEvent]] = Array(repeating: [], count: 7)
        var barCountByDay: [Int] = Array(repeating: 0, count: 7)
    }

    private var days: [Date] {
        (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: weekStart)! }
    }

    var body: some View {
        let layout = makeLayout()
        let dayList = days
        let safeHeight: CGFloat = minRowHeight.isFinite ? min(max(minRowHeight, 0), 2000) : 80
        let rowsFit = max(WeekMetrics.maxRows, Int((safeHeight - 30) / 20))

        HStack(alignment: .top, spacing: WeekMetrics.columnSpacing) {
            ForEach(0..<7, id: \.self) { col in
                let limit = max(1, rowsFit - layout.laneCount)
                let shown = Array(sortedForDay(layout.singlesByDay[col]).prefix(limit))
                let overflow = layout.allByDay[col].count - layout.barCountByDay[col] - shown.count

                DayCell(
                    day: dayList[col],
                    singles: shown,
                    overflow: max(overflow, 0),
                    laneCount: layout.laneCount,
                    allEvents: sortedForDay(layout.allByDay[col]),
                    onSelect: onSelect,
                    onShowDay: onShowDay,
                    minHeight: minRowHeight
                )
            }
        }
        .overlay(alignment: .topLeading) {
            barsOverlay(layout)
        }
    }

    // Works out which events are bars, which lane each bar sits in, and what is left for each day.
    private func makeLayout() -> WeekLayout {
        let cal = Calendar.current
        var result = WeekLayout()
        let weekFirstDay = cal.startOfDay(for: weekStart)

        struct Span {
            let event: EKEvent
            let startCol: Int
            let endCol: Int
            let before: Bool
            let after: Bool
        }
        var spans: [Span] = []

        for event in events {
            guard let start = event.startDate, let end = event.endDate else { continue }

            let lastMoment = end > start ? end.addingTimeInterval(-1) : start
            let firstDay = cal.startOfDay(for: start)
            let lastDay = cal.startOfDay(for: lastMoment)

            let rawStart = cal.dateComponents([.day], from: weekFirstDay, to: firstDay).day ?? 0
            let rawEnd = cal.dateComponents([.day], from: weekFirstDay, to: lastDay).day ?? 0
            if rawEnd < 0 || rawStart > 6 { continue }

            let startCol = max(rawStart, 0)
            let endCol = min(rawEnd, 6)

            for col in startCol...endCol {
                result.allByDay[col].append(event)
            }

            if rawEnd > rawStart {
                spans.append(Span(event: event, startCol: startCol, endCol: endCol,
                                  before: rawStart < 0, after: rawEnd > 6))
            } else {
                result.singlesByDay[startCol].append(event)
            }
        }

        spans.sort {
            if $0.startCol != $1.startCol { return $0.startCol < $1.startCol }
            return ($0.endCol - $0.startCol) > ($1.endCol - $1.startCol)
        }

        var laneEnds: [Int] = []
        for span in spans {
            var lane = -1
            for i in 0..<laneEnds.count where laneEnds[i] < span.startCol {
                lane = i
                break
            }
            if lane == -1 {
                if laneEnds.count >= WeekMetrics.maxLanes { continue }
                laneEnds.append(span.endCol)
                lane = laneEnds.count - 1
            } else {
                laneEnds[lane] = span.endCol
            }
            result.bars.append(Bar(event: span.event, startCol: span.startCol, endCol: span.endCol,
                                   lane: lane, continuesBefore: span.before, continuesAfter: span.after))
            for col in span.startCol...span.endCol {
                result.barCountByDay[col] += 1
            }
        }
        result.laneCount = laneEnds.count
        return result
    }

    private func barsOverlay(_ layout: WeekLayout) -> some View {
        GeometryReader { geo in
            let gap = WeekMetrics.columnSpacing
            let cellW = (geo.size.width - 6 * gap) / 7

            ForEach(Array(layout.bars.enumerated()), id: \.offset) { _, bar in
                let span = CGFloat(bar.endCol - bar.startCol + 1)
                let width = max(span * cellW + (span - 1) * gap, 0)
                let x = CGFloat(bar.startCol) * (cellW + gap)
                let y = WeekMetrics.cellPadding + WeekMetrics.headerHeight + WeekMetrics.cellSpacing
                    + CGFloat(bar.lane) * (WeekMetrics.laneHeight + WeekMetrics.laneGap)

                barView(bar, width: width)
                    .offset(x: x, y: y)
            }
        }
    }

    private func barView(_ bar: Bar, width: CGFloat) -> some View {
        let eventColor = calendarColor(for: bar.event)
        let r: CGFloat = 4
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: bar.continuesBefore ? 0 : r,
            bottomLeadingRadius: bar.continuesBefore ? 0 : r,
            bottomTrailingRadius: bar.continuesAfter ? 0 : r,
            topTrailingRadius: bar.continuesAfter ? 0 : r
        )

        return Text(bar.event.title ?? "Untitled")
            .font(.caption2)
            .lineLimit(1)
            .padding(.leading, bar.continuesBefore ? 4 : 7)
            .padding(.trailing, 4)
            .frame(width: width, height: WeekMetrics.laneHeight, alignment: .leading)
            .background(eventColor.opacity(0.35))
            .overlay(alignment: .leading) {
                if !bar.continuesBefore {
                    Rectangle()
                        .fill(eventColor)
                        .frame(width: 3)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { onSelect(bar.event) }
    }
}

struct DayCell: View {
    let day: Date
    let singles: [EKEvent]
    let overflow: Int
    let laneCount: Int
    let allEvents: [EKEvent]
    let onSelect: (EKEvent) -> Void
    let onShowDay: (Date, [EKEvent]) -> Void
    var minHeight: CGFloat = 80

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.highlightedDays) private var highlightedDays
    @AppStorage("showEventTimes") private var showTimes = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    private var isEvenMonth: Bool {
        Calendar.current.component(.month, from: day) % 2 == 0
    }

    private var isHighlighted: Bool {
        guard let highlightedDays else { return false }
        return highlightedDays.contains(Calendar.current.startOfDay(for: day))
    }

    private var headerText: String {
        let isFirst = Calendar.current.component(.day, from: day) == 1
        return day.formatted(
            isFirst
                ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                : .dateTime.weekday(.abbreviated).day()
        )
    }

    private func label(for event: EKEvent) -> String {
        let title = event.title ?? "Untitled"
        guard showTimes,
              !event.isAllDay,
              Calendar.current.isDate(event.startDate, inSameDayAs: day) else {
            return title
        }
        let time = event.startDate.formatted(.dateTime.hour().minute())
        if title.hasPrefix("○ ") {
            return "○ \(time) " + String(title.dropFirst(2))
        }
        return "\(time) \(title)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekMetrics.cellSpacing) {
            Text(headerText)
                .font(.caption.bold())
                .padding(.horizontal, 4)
                .background(isToday ? Color.red : Color.clear)
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .clipShape(Capsule())
                .frame(height: WeekMetrics.headerHeight)

            if laneCount > 0 {
                Color.clear
                    .frame(height: CGFloat(laneCount) * (WeekMetrics.laneHeight + WeekMetrics.laneGap))
            }

            ForEach(Array(singles.enumerated()), id: \.offset) { item in
                let eventColor = calendarColor(for: item.element)
                Text(label(for: item.element))
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.vertical, 2)
                    .padding(.leading, 6)
                    .padding(.trailing, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .eventChipStyle(isReminder: item.element.isReminderItem, color: eventColor,
                                    radius: 3, tint: 0.25, stripe: 3)
                    .onTapGesture { onSelect(item.element) }
            }

            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(.caption2.bold())
                    .foregroundStyle(.blue)
                    .onTapGesture { onShowDay(day, allEvents) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: max(minHeight - WeekMetrics.cellPadding * 2, 0), alignment: .topLeading)
        .padding(WeekMetrics.cellPadding)
        .background(
            isHighlighted
                ? Color.accentColor.opacity(0.25)
                : (isToday
                    ? Color.red.opacity(0.12)
                    : Color.gray.opacity(isEvenMonth ? 0.08 : (colorScheme == .dark ? 0.32 : 0.22)))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted ? Color.accentColor : (isToday ? Color.red : Color.clear), lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.25), value: isHighlighted)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onShowDay(day, allEvents) }
    }
}
