import AppKit
import SwiftUI

// Compiled as a separate test executable; never included in the shipped app.
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03)) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let p = Preferences()
p.language = "it_IT"; p.firstWeekday = 2; p.textSize = 1; p.panelHeight = 1
p.weekNumbers = false; p.openToday = true
let scroll = CalendarScrollView(preferences: p)
let root = CalendarPopover(preferences: p, viewport: scroll.viewport, scroll: scroll, settings: {}, quit: {})
let host = NSHostingView(rootView: root)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 328, height: p.height),
    styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = host
window.makeKeyAndOrderFront(nil)
host.layoutSubtreeIfNeeded()
settle()
scroll.open()
settle()
check(scroll.contentSize.width > 250, "Native scroll has a valid width")
check(scroll.contentSize.height > 130 && scroll.contentSize.height < 200, "Native scroll has a month-sized height")
check(p.height < 280, "Default popover is approximately one month tall")
check(!scroll.hasVerticalScroller && scroll.contentSize.width == host.bounds.width, "Fixed weekdays align with the grid without a scrollbar gutter")
let current = p.engine.startOfWeek(containing: p.engine.month(containing: Date()).start)
check(scroll.calendarView.weeks.entries[scroll.calendarView.weeks.index(at: Double(scroll.contentView.bounds.minY))].start == current,
    "Open positions the native clip view on the current month’s first week")

for i in 0..<40 {
    let weeks = scroll.calendarView.weeks
    let entry = weeks.entries[i < 20 ? 300 : 10]
    scroll.contentView.scroll(to: NSPoint(x: 0, y: entry.y + 17.375))
    scroll.reflectScrolledClipView(scroll.contentView)
    settle()
    let adjusted = scroll.calendarView.weeks
    let index = adjusted.index(at: Double(scroll.contentView.bounds.minY))
    check(adjusted.entries[index].start == entry.start, "Native recenter preserves visible week")
    check(abs(Double(scroll.contentView.bounds.minY) - adjusted.entries[index].y - 17.375) < 0.001,
        "Native recenter preserves fractional pixel offset")
    check(adjusted.entries.count == 313, "Native week storage remains bounded")
    let expectedMonth = adjusted.visibleMonth(origin: Double(scroll.contentView.bounds.minY), viewportHeight: Double(scroll.contentSize.height))
    check(scroll.viewport.month == expectedMonth, "Pinned month updates while scrolling: iteration \(i), title \(scroll.viewport.month), expected \(expectedMonth)")
}

let sixWeekMonthEnd = p.engine.calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!
scroll.goTo(sixWeekMonthEnd, animated: false)
settle()
let endRow = scroll.calendarView.weeks.offset(for: sixWeekMonthEnd)!
check(endRow >= Double(scroll.contentView.bounds.minY) && endRow + Double(p.rowHeight) <= Double(scroll.contentView.bounds.maxY) + 0.001,
    "Today navigation reveals the requested day even in a six-week month")

scroll.goTo(Date(), animated: false)
settle()
for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
    window.appearance = NSAppearance(named: appearance)
    p.weekNumbers = true; p.textSize = 1
    scroll.configure()
    host.layoutSubtreeIfNeeded()
    settle()
    check((scroll.calendarView.accessibilityChildren()?.count ?? 0) > 20, "VoiceOver exposes visible dates")
    let rect = host.bounds
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: rect) else { check(false, "Create render bitmap"); exit(1) }
    host.cacheDisplay(in: rect, to: bitmap)
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: "build/native-\(name).png"))
    check(data.count > 2000, "Native \(name) rendering contains content")
}

scroll.remember()
let visible = scroll.calendarView.weeks.entries[scroll.calendarView.weeks.index(at: Double(scroll.contentView.bounds.minY))]
check(p.engine.startOfWeek(containing: p.lastWeek) == visible.start, "Remembered week matches view")
p.openToday = false
let beforeClose = scroll.contentView.bounds.minY
scroll.goTo(p.engine.addingMonths(3, to: Date()), animated: false)
scroll.open()
settle()
check(abs(scroll.contentView.bounds.minY - beforeClose) < 0.001, "Reopening restores the exact weekly scroll position")

let fixedDay = p.engine.calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
let nextDay = p.engine.calendar.date(byAdding: .day, value: 1, to: fixedDay)!
check(StatusDayIcon.dayText(date: fixedDay, calendar: p.engine.calendar, locale: p.locale) == "14", "Menu bar shows the day number")
check(StatusDayIcon.dayText(date: nextDay, calendar: p.engine.calendar, locale: p.locale) == "15", "Day number updates after midnight")
let badge = StatusDayIcon.make(date: fixedDay, calendar: p.engine.calendar, locale: p.locale)
check(badge.isTemplate && badge.size == NSSize(width: 28, height: 18), "Day badge adapts to menu bar appearance")
if let rep = NSBitmapImageRep(data: badge.tiffRepresentation!), let png = rep.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: "build/native-day-icon.png"))
    let colors = (4..<(rep.pixelsHigh - 4)).flatMap { y in
        (4..<(rep.pixelsWide - 4)).compactMap { x in rep.colorAt(x: x, y: y)?.alphaComponent }
    }
    check(colors.contains(where: { $0 < 0.1 }) && colors.contains(where: { $0 > 0.9 }), "Badge number is cut out of its rounded background")
} else { check(false, "Menu bar badge renders") }

let week = scroll.calendarView.weeks.entries[scroll.calendarView.weeks.index(at: Double(scroll.contentView.bounds.minY))]
let saturday = week.days.first(where: { p.engine.calendar.component(.weekday, from: $0) == 7 })!
let color = scroll.calendarView.dayColor(for: saturday, now: fixedDay).usingColorSpace(.sRGB)!
if !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
    check(abs(color.alphaComponent - 0.82) < 0.001, "Weekend text is only slightly dimmed")
}
for column in 0..<7 {
    let rect = scroll.calendarView.cellFrame(entry: week, day: column)
    check(scroll.calendarView.date(at: NSPoint(x: rect.midX, y: rect.midY)) == week.days[column], "Every visible day has a correct hit target")
}

print("PASS: continuous weekly layout, pinned month updates, compact height, day-number badge, readable weekends, 40 bidirectional recentrings, fractional offsets, bounded storage, VoiceOver labels, light/dark rendering, day hit targets and position persistence.")
window.orderOut(nil)
