//
//  SidebarView.swift
//  Panorama Cal
//
//  Created by Donald Edwards on 10/11/2026.
//

import SwiftUI
import EventKit

// Set to true to bring back the single-month range option.
let oneMonthEnabled = true

struct SidebarView: View {
    let calendar: CalendarStore
    @Binding var months: Int

    @AppStorage("showEventTimes") private var showTimes = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("viewMode") private var viewMode = "calendar"
    @AppStorage("collapsedAccounts") private var collapsedRaw = ""

    private struct AccountGroup: Identifiable {
        let name: String
        let calendars: [EKCalendar]
        var id: String { name }
    }

    private enum GroupState {
        case none, some, all
    }

    // Accounts named here are listed first, in this order. Anything else follows alphabetically.
    private let accountOrder = ["iCloud"]

    private var groups: [AccountGroup] {
        let dict = Dictionary(grouping: calendar.calendars) { $0.source?.title ?? "Other" }
        let names = dict.keys.sorted { a, b in
            let ia = accountOrder.firstIndex(of: a) ?? Int.max
            let ib = accountOrder.firstIndex(of: b) ?? Int.max
            if ia != ib { return ia < ib }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return names.map { name in
            AccountGroup(
                name: name,
                calendars: (dict[name] ?? []).sorted { $0.title < $1.title }
            )
        }
    }

    private var collapsedSet: Set<String> {
        Set(collapsedRaw.split(separator: "|").map(String.init))
    }

    private func expandedBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSet.contains(name) },
            set: { isOpen in
                var set = collapsedSet
                if isOpen { set.remove(name) } else { set.insert(name) }
                collapsedRaw = set.sorted().joined(separator: "|")
            }
        )
    }

    private func visibleCount(_ group: AccountGroup) -> Int {
        group.calendars.filter { calendar.isVisible($0) }.count
    }

    private func groupState(_ group: AccountGroup) -> GroupState {
        let n = visibleCount(group)
        if n == 0 { return .none }
        return n == group.calendars.count ? .all : .some
    }

    private func setGroup(_ group: AccountGroup, visible: Bool) {
        for cal in group.calendars where calendar.isVisible(cal) != visible {
            calendar.toggle(cal)
        }
    }
    
    private func calendarBinding(_ cal: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { calendar.isVisible(cal) },
            set: { _ in calendar.toggle(cal) }
        )
    }

    @ViewBuilder
    private func calendarRow(_ cal: EKCalendar) -> some View {
        #if os(iOS)
        HStack(spacing: 8) {
            Circle()
                .fill(Color(cgColor: cal.cgColor))
                .frame(width: 10, height: 10)
            Text(cal.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Toggle("", isOn: calendarBinding(cal))
                .labelsHidden()
                .fixedSize()
        }
        .padding(.trailing, 2)
        #else
        Toggle(isOn: calendarBinding(cal)) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(cgColor: cal.cgColor))
                    .frame(width: 10, height: 10)
                Text(cal.title)
                    .lineLimit(1)
            }
        }
        #endif
    }

    private func groupCheckbox(_ group: AccountGroup) -> some View {
        let state = groupState(group)
        return Button {
            setGroup(group, visible: state != .all)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(state == .none ? Color.clear : Color.accentColor.opacity(state == .all ? 1 : 0.45))
                RoundedRectangle(cornerRadius: 4)
                    .stroke(state == .none ? Color.secondary.opacity(0.6) : Color.accentColor, lineWidth: 1)
                if state == .all {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show or hide all calendars in \(group.name)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("View")
                    .font(.headline)
                Picker("View", selection: $viewMode) {
                    Text("Overview").tag("overview")
                    Text("Planner").tag("planner")
                    Text("Calendar").tag("calendar")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Range (months)")
                    .font(.headline)
                Picker("Range", selection: $months) {
                    if oneMonthEnabled {
                        Text("1").tag(1)
                    }
                    Text("3").tag(3)
                    Text("6").tag(6)
                    Text("12").tag(12)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Display")
                    .font(.headline)
                Toggle("Show event times", isOn: $showTimes)

                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Calendars")
                    .font(.headline)

                HStack(spacing: 16) {
                    Button("Show All") { calendar.showAll() }
                    Button("Hide All") { calendar.hideAll() }
                }
                .buttonStyle(.borderless)
                .font(.callout)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groups) { group in
                            DisclosureGroup(isExpanded: expandedBinding(group.name)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                                        calendarRow(cal)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                                .padding(.leading, 24)
                            } label: {
                                HStack(spacing: 8) {
                                    groupCheckbox(group)
                                    Text(group.name)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    Text("\(visibleCount(group))/\(group.calendars.count)")
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.gray.opacity(0.08))
    }
}
