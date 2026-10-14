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
check(p.panelHeight == 2, "Extended is the default panel height")
p.language = "it_IT"; p.firstWeekday = 2; p.textSize = 1; p.panelHeight = 2
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
check(scroll.contentSize.height > 180 && scroll.contentSize.height < 230, "Default native scroll fits approximately six weeks")
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
    check(scroll.calendarView.emphasizedMonth == expectedMonth, "Day emphasis follows the exact month in the pinned title")
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
    scroll.calendarView.setEmphasizedMonth(scroll.viewport.month, animated: false)
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
check(badge.isTemplate && badge.size == NSSize(width: 18, height: 16), "Day badge is small, slightly flattened and adapts to menu bar appearance")
if let rep = NSBitmapImageRep(data: badge.tiffRepresentation!), let png = rep.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: "build/native-day-icon.png"))
    let colors = (4..<(rep.pixelsHigh - 4)).flatMap { y in
        (4..<(rep.pixelsWide - 4)).compactMap { x in rep.colorAt(x: x, y: y)?.alphaComponent }
    }
    check(colors.contains(where: { $0 < 0.1 }) && colors.contains(where: { $0 > 0.9 }), "Badge number is cut out of its rounded background")
} else { check(false, "Menu bar badge renders") }

let week = scroll.calendarView.weeks.entries[scroll.calendarView.weeks.index(at: Double(scroll.contentView.bounds.minY))]
let saturday = week.days.first(where: { p.engine.calendar.component(.weekday, from: $0) == 7 })!
scroll.calendarView.setEmphasizedMonth(saturday, animated: false)
let color = scroll.calendarView.dayColor(for: saturday, now: fixedDay).usingColorSpace(.sRGB)!
if !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
    check(abs(color.alphaComponent - 0.72) < 0.001, "Weekend text is a little grayer within the active month")
}
for column in 0..<7 {
    let rect = scroll.calendarView.cellFrame(entry: week, day: column)
    check(scroll.calendarView.date(at: NSPoint(x: rect.midX, y: rect.midY)) == week.days[column], "Every visible day has a correct hit target")
}

let activeDay = p.engine.calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
let activeWeekend = p.engine.calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
let previousDay = p.engine.calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!
let nextMonthDay = p.engine.calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
let adjacentOpacity: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.60 : 0.38
let weekendOpacity: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.90 : 0.72
let document = scroll.calendarView
document.setEmphasizedMonth(activeDay, animated: false)
check(abs(document.textOpacity(for: activeDay) - 1) < 0.001, "Selected-month weekdays have full foreground contrast")
check(abs(document.textOpacity(for: previousDay) - adjacentOpacity) < 0.001, "Previous month is gray")
check(abs(document.textOpacity(for: nextMonthDay) - adjacentOpacity) < 0.001, "Next month is gray")
check(abs(document.textOpacity(for: activeWeekend) - weekendOpacity) < 0.001, "Active-month weekends are subtly gray")
p.weekends = false
check(abs(document.textOpacity(for: activeWeekend) - 1) < 0.001, "Weekend dimming can be disabled")
check(abs(document.textOpacity(for: nextMonthDay) - adjacentOpacity) < 0.001, "Adjacent-month dimming is independent of the weekend preference")
p.weekends = true
settle()

// Isolate the animation clock from SwiftUI layout notifications. The actual
// hosted view and its header were already checked through 40 native scrolls.
let animationDocument = CalendarDocumentView(preferences: p)
animationDocument.setEmphasizedMonth(activeDay, animated: false)
animationDocument.setEmphasizedMonth(nextMonthDay, animated: true, reduceMotion: false)
check(animationDocument.monthAnimationTimer != nil && animationDocument.monthAnimationProgress == 0, "Month transition starts gently")
check(abs(animationDocument.textOpacity(for: activeDay) - 1) < 0.001, "Outgoing month does not jump at transition start")
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
let intermediate = animationDocument.textOpacity(for: activeDay)
check(intermediate > adjacentOpacity && intermediate < 1, "Outgoing month fades gradually: opacity \(intermediate), progress \(animationDocument.monthAnimationProgress)")
animationDocument.setEmphasizedMonth(activeDay, animated: true, reduceMotion: false)
check(abs(animationDocument.textOpacity(for: activeDay) - intermediate) < 0.001, "Reversing a transition preserves its current shade")
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.24))
check(abs(animationDocument.textOpacity(for: activeDay) - 1) < 0.001 && animationDocument.monthAnimationTimer == nil, "Transition finishes and stops its timer")
animationDocument.setEmphasizedMonth(nextMonthDay, animated: true, reduceMotion: true)
check(animationDocument.monthAnimationTimer == nil && abs(animationDocument.textOpacity(for: nextMonthDay) - 1) < 0.001, "Reduce Motion switches emphasis without animation")
check(abs(animationDocument.textOpacity(for: activeDay) - adjacentOpacity) < 0.001, "Outgoing month becomes gray after switching")

document.setEmphasizedMonth(scroll.viewport.month, animated: false)
print("PASS: continuous weekly layout, pinned month emphasis, adjacent-month dimming, readable weekends, animated and reversed transitions, Reduce Motion, small flattened day badge, 40 bidirectional recentrings, fractional offsets, VoiceOver labels, rendering and position persistence.")
window.orderOut(nil)
