//
//  ReminderStyle.swift
//  PanoCal
//
//  Created by Donald Edwards on 16/11/2026.
//

import SwiftUI
import EventKit

extension EKEvent {
    // Reminders are shown through stand-in events, which carry this marker address.
    var isReminderItem: Bool {
        url?.scheme == "panocal-reminder"
    }

    // The title without the reminder's ○, for places that already show a ring beside it.
    var cleanTitle: String {
        let text = title ?? "Untitled"
        return isReminderItem && text.hasPrefix("○ ") ? String(text.dropFirst(2)) : text
    }
}

// Events are a tinted chip with a coloured stripe. Reminders are a hollow chip with a dashed outline.
struct EventChipStyle: ViewModifier {
    let isReminder: Bool
    let color: Color
    let radius: CGFloat
    let tint: Double
    let stripe: CGFloat

    func body(content: Content) -> some View {
        if isReminder {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                )
        } else {
            content
                .background(color.opacity(tint))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(color)
                        .frame(width: stripe)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius))
        }
    }
}

extension View {
    func eventChipStyle(isReminder: Bool, color: Color, radius: CGFloat, tint: Double, stripe: CGFloat) -> some View {
        modifier(EventChipStyle(isReminder: isReminder, color: color, radius: radius, tint: tint, stripe: stripe))
    }
}

// The small dot beside an event: filled for events, a hollow ring for reminders.
struct EventDot: View {
    let event: EKEvent
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        if event.isReminderItem {
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
    }
}
