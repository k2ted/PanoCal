//
//  OverviewView.swift
//  PanoCal
//
//  Created by Donald Edwards on 13/11/2026.
//

import SwiftUI
import EventKit

private func overviewColor(for event: EKEvent) -> Color {
    if let cg = event.calendar?.cgColor {
        return Color(cgColor: cg)
    }
    return .blue
}

private func overviewSorted(_ list: [EKEvent]) -> [EKEvent] {
    list.sorted { a, b in
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        return a.startDate < b.startDate
    }
}

// An event, plus the first and last day it covers, counted in days from the start of the range.
private struct OverviewItem {
    let event: EKEvent
    let first: Int
    let last: Int
}

private enum OverviewMetrics {
    static func dateHeight(_ roomy: Bool) -> CGFloat { roomy ? 13 : 10 }
    static func laneHeight(_ roomy: Bool) -> CGFloat { roomy ? 12 : 3 }
    static func laneStep(_ roomy: Bool) -> CGFloat { roomy ? 14 : 5 }
}

struct OverviewView: View {
    let calendar: CalendarStore
    let months: Int
    let startMonth: Date
    let onSelect: (EKEvent) -> Void
    let onShowDay: (Date, [EKEvent]) -> Void

    private var monthStarts: [Date] {
        let cal = Calendar.current
        let first = cal.dateInterval(of: .month, for: startMonth)?.start ?? startMonth
        return (0..<months).compactMap { cal.date(byAdding: .month, value: $0, to: first) }
    }

    // Works out each event's day numbers once, and which events fall on each day.
    private func prepare(events: [EKEvent], rangeStart: Date, totalDays: Int) -> (items: [OverviewItem], dayLists: [[Int]]) {
        let cal = Calendar.current
        var items: [OverviewItem] = []

        for event in events {
            guard let start = event.startDate, let end = event.endDate else { continue }
            let lastMoment = end > start ? end.addingTimeInterval(-1) : start
            let first = cal.dateComponents([.day], from: rangeStart, to: cal.startOfDay(for: start)).day ?? 0
            let last = cal.dateComponents([.day], from: rangeStart, to: cal.startOfDay(for: lastMoment)).day ?? 0
            if last < 0 || first > totalDays - 1 { continue }
            items.append(OverviewItem(event: event, first: first, last: max(last, first)))
        }

        var dayLists: [[Int]] = Array(repeating: [], count: max(totalDays, 0))
        for (i, item) in items.enumerated() {
            let lo = max(item.first, 0)
            let hi = min(item.last, totalDays - 1)
            if lo <= hi {
                for d in lo...hi {
                    dayLists[d].append(i)
                }
            }
        }
        return (items, dayLists)
    }

    // How many tiles across and down, depending on the range and the window's shape.
    private func arrangement(width: CGFloat, height: CGFloat) -> (cols: Int, rows: Int) {
        let landscape = width >= height
        switch months {
        case 1: return (1, 1)
        case 3: return landscape ? (3, 1) : (1, 3)
        case 6: return landscape ? (3, 2) : (2, 3)
        default: return landscape ? (4, 3) : (3, 4)
        }
    }

    var body: some View {
        let events = calendar.visibleEvents      // one snapshot, used for everything below
        let starts = monthStarts
        let cal = Calendar.current
        let rangeStart = starts.first ?? Date()
        let rangeEnd = cal.date(byAdding: .month, value: months, to: rangeStart) ?? rangeStart
        let totalDays = cal.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 0
        let prepared = prepare(events: events, rangeStart: rangeStart, totalDays: totalDays)

        GeometryReader { geo in
            let outerPad: CGFloat = 12
            let tileGap: CGFloat = 10
            let grid = arrangement(width: geo.size.width, height: geo.size.height)
            let tileW = (geo.size.width - outerPad * 2 - tileGap * CGFloat(grid.cols - 1)) / CGFloat(grid.cols)
            let tileH = (geo.size.height - outerPad * 2 - tileGap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)

            VStack(spacing: tileGap) {
                ForEach(0..<grid.rows, id: \.self) { r in
                    HStack(spacing: tileGap) {
                        ForEach(0..<grid.cols, id: \.self) { c in
                            let index = r * grid.cols + c
                            if index < starts.count {
                                let startIdx = cal.dateComponents([.day], from: rangeStart, to: starts[index]).day ?? 0
                                MonthTile(
                                    monthStart: starts[index],
                                    monthStartIdx: startIdx,
                                    items: prepared.items,
                                    dayLists: prepared.dayLists,
                                    width: tileW,
                                    height: tileH,
                                    onSelect: onSelect,
                                    onShowDay: onShowDay
                                )
                            } else {
                                Color.clear.frame(width: tileW, height: tileH)
                            }
                        }
                    }
                }
            }
            .padding(outerPad)
        }
    }
}

private struct MonthTile: View {
    let monthStart: Date
    let monthStartIdx: Int
    let items: [OverviewItem]
    let dayLists: [[Int]]
    let width: CGFloat
    let height: CGFloat
    let onSelect: (EKEvent) -> Void
    let onShowDay: (Date, [EKEvent]) -> Void

    private struct RowBar {
        let item: Int
        let startCol: Int
        let endCol: Int
        let lane: Int
        let before: Bool
        let after: Bool
    }

    private struct RowLayout {
        var bars: [RowBar] = []
        var lanedItems: Set<Int> = []
        var lanesUsedByCol: [Int] = Array(repeating: 0, count: 7)
    }

    private var weekdaySymbols: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // Decides which multi-day events draw as bars in one week row, and which lane each sits in.
    private func makeRowLayout(rowFirstIdx: Int, lo: Int, hi: Int, maxLanes: Int) -> RowLayout {
        var result = RowLayout()

        struct Span {
            let item: Int
            let startCol: Int
            let endCol: Int
            let before: Bool
            let after: Bool
        }
        var spans: [Span] = []

        for (i, item) in items.enumerated() where item.last > item.first {
            let rawStart = item.first - rowFirstIdx
            let rawEnd = item.last - rowFirstIdx
            if rawEnd < lo || rawStart > hi { continue }
            spans.append(Span(
                item: i,
                startCol: max(rawStart, lo),
                endCol: min(rawEnd, hi),
                before: rawStart < lo,
                after: rawEnd > hi
            ))
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
                if laneEnds.count >= maxLanes { continue }
                laneEnds.append(span.endCol)
                lane = laneEnds.count - 1
            } else {
                laneEnds[lane] = span.endCol
            }
            result.bars.append(RowBar(
                item: span.item,
                startCol: span.startCol,
                endCol: span.endCol,
                lane: lane,
                before: span.before,
                after: span.after
            ))
            result.lanedItems.insert(span.item)
            for col in span.startCol...span.endCol {
                result.lanesUsedByCol[col] = max(result.lanesUsedByCol[col], lane + 1)
            }
        }
        return result
    }

    @ViewBuilder
    private func barView(_ bar: RowBar, cellW: CGFloat, gap: CGFloat, roomy: Bool) -> some View {
        let span = CGFloat(bar.endCol - bar.startCol + 1)
        let barWidth = max(span * cellW + (span - 1) * gap - 2, 0)
        let event = items[bar.item].event
        let color = overviewColor(for: event)
        let r: CGFloat = roomy ? 2 : 1.5
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: bar.before ? 0 : r,
            bottomLeadingRadius: bar.before ? 0 : r,
            bottomTrailingRadius: bar.after ? 0 : r,
            topTrailingRadius: bar.after ? 0 : r
        )

        if roomy {
            Text(event.title ?? "Untitled")
                .font(.system(size: 8.5))
                .lineLimit(1)
                .padding(.leading, bar.before ? 3 : 5)
                .padding(.trailing, 2)
                .frame(width: barWidth, height: OverviewMetrics.laneHeight(true), alignment: .leading)
                .background(color.opacity(0.35))
                .overlay(alignment: .leading) {
                    if !bar.before {
                        Rectangle()
                            .fill(color)
                            .frame(width: 2)
                    }
                }
                .clipShape(shape)
                .contentShape(shape)
                .onTapGesture { onSelect(event) }
        } else {
            shape
                .fill(color)
                .frame(width: barWidth, height: OverviewMetrics.laneHeight(false))
        }
    }

    private func weekRow(d0: Int, dayCount: Int, layout: RowLayout, cellW: CGFloat, cellH: CGFloat,
                         gap: CGFloat, roomy: Bool) -> some View {
        let cal = Calendar.current
        let laneStep = OverviewMetrics.laneStep(roomy)
        let headerOffset = 2 + OverviewMetrics.dateHeight(roomy) + 2

        return HStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { c in
                let day = d0 + c
                if day >= 1 && day <= dayCount,
                   let date = cal.date(byAdding: .day, value: day - 1, to: monthStart) {
                    let dayIdx = monthStartIdx + day - 1
                    let idxList = dayLists.indices.contains(dayIdx) ? dayLists[dayIdx] : []
                    let all = overviewSorted(idxList.map { items[$0].event })
                    let chips = overviewSorted(
                        idxList.filter { !layout.lanedItems.contains($0) }.map { items[$0].event }
                    )

                    OverviewDayCell(
                        date: date,
                        chips: chips,
                        allEvents: all,
                        width: cellW,
                        height: cellH,
                        roomy: roomy,
                        reserve: CGFloat(layout.lanesUsedByCol[c]) * laneStep,
                        onSelect: onSelect,
                        onShowDay: onShowDay
                    )
                } else {
                    Color.clear.frame(width: cellW, height: cellH)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.bars.enumerated()), id: \.offset) { _, bar in
                    barView(bar, cellW: cellW, gap: gap, roomy: roomy)
                        .offset(
                            x: CGFloat(bar.startCol) * (cellW + gap) + 1,
                            y: headerOffset + CGFloat(bar.lane) * laneStep
                        )
                }
            }
        }
    }

    var body: some View {
        let cal = Calendar.current
        let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let weekday = cal.component(.weekday, from: monthStart)
        let offset = (weekday - cal.firstWeekday + 7) % 7

        let cellGap: CGFloat = 1
        let innerW = max(width - 12, 10)
        let titleH: CGFloat = 18
        let weekdayH: CGFloat = 12
        let gridH = max(height - 12 - titleH - weekdayH - 4, 10)
        let cellW = max((innerW - cellGap * 6) / 7, 4)
        let cellH = max((gridH - cellGap * 5) / 6, 4)
        let roomy = cellW >= 80 && cellH >= 40
        let maxLanes = roomy ? (cellH >= 80 ? 3 : 2) : 2

        VStack(spacing: 2) {
            Text(monthStart.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 12, weight: .bold))
                .frame(height: titleH)

            HStack(spacing: cellGap) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: cellW, height: weekdayH)
                }
            }

            VStack(spacing: cellGap) {
                ForEach(0..<6, id: \.self) { r in
                    let d0 = r * 7 - offset + 1
                    let lo = max(0, 1 - d0)
                    let hi = min(6, dayCount - d0)

                    if lo <= hi {
                        let rowLayout = makeRowLayout(
                            rowFirstIdx: monthStartIdx + d0 - 1,
                            lo: lo,
                            hi: hi,
                            maxLanes: maxLanes
                        )
                        weekRow(d0: d0, dayCount: dayCount, layout: rowLayout, cellW: cellW,
                                cellH: cellH, gap: cellGap, roomy: roomy)
                    } else {
                        Color.clear.frame(height: cellH)
                    }
                }
            }
        }
        .padding(6)
        .frame(width: width, height: height, alignment: .top)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct OverviewDayCell: View {
    let date: Date
    let chips: [EKEvent]
    let allEvents: [EKEvent]
    let width: CGFloat
    let height: CGFloat
    let roomy: Bool
    let reserve: CGFloat
    let onSelect: (EKEvent) -> Void
    let onShowDay: (Date, [EKEvent]) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.highlightedDays) private var highlightedDays

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var isWeekend: Bool {
        Calendar.current.isDateInWeekend(date)
    }

    private var isHighlighted: Bool {
        guard let highlightedDays else { return false }
        return highlightedDays.contains(Calendar.current.startOfDay(for: date))
    }

    private var cellBackground: Color {
        if isHighlighted { return Color.accentColor.opacity(0.25) }
        if isToday { return Color.red.opacity(0.12) }
        if isWeekend { return Color.gray.opacity(colorScheme == .dark ? 0.30 : 0.20) }
        return Color.gray.opacity(colorScheme == .dark ? 0.14 : 0.07)
    }

    private func chip(_ event: EKEvent) -> some View {
        let color = overviewColor(for: event)
        return Text(event.title ?? "Untitled")
            .font(.system(size: 8.5))
            .lineLimit(1)
            .padding(.leading, 4)
            .padding(.trailing, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 12)
            .eventChipStyle(isReminder: event.isReminderItem, color: color, radius: 2, tint: 0.3, stripe: 2)
            .onTapGesture { onSelect(event) }
    }

    @ViewBuilder
    private func bar(_ event: EKEvent) -> some View {
        if event.isReminderItem {
            Capsule()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(height: 3)
                .padding(.horizontal, 2)
        } else {
            Capsule()
                .fill(overviewColor(for: event))
                .frame(height: 3)
                .padding(.horizontal, 2)
        }
    }

    var body: some View {
        let dateH = OverviewMetrics.dateHeight(roomy)
        let lineH: CGFloat = roomy ? 14 : 5
        let available = height - 2 - dateH - 2 - reserve - 2
        let capacity = max(1, Int(available / lineH))
        let overflowing = chips.count > capacity
        let shownCount = (overflowing && roomy) ? max(capacity - 1, 1) : min(chips.count, capacity)
        let shown = Array(chips.prefix(shownCount))
        let overflow = chips.count - shown.count

        VStack(alignment: .leading, spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: roomy ? 10 : 8, weight: .semibold))
                .padding(.horizontal, 3)
                .background(isToday ? Color.red : Color.clear)
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .clipShape(Capsule())
                .frame(height: dateH)
                .padding(.leading, 2)

            if reserve > 0 {
                Color.clear
                    .frame(height: reserve)
            }

            if roomy {
                ForEach(Array(shown.enumerated()), id: \.offset) { item in
                    chip(item.element)
                }
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.leading, 3)
                }
            } else {
                ForEach(Array(shown.enumerated()), id: \.offset) { item in
                    bar(item.element)
                }
            }
        }
        .padding(.top, 2)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(cellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isHighlighted ? Color.accentColor : (isToday ? Color.red : Color.clear), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onShowDay(date, allEvents) }
    }
}
