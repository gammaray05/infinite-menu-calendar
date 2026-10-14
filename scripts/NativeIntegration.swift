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
let clock = CalendarClock()
let scroll = CalendarScrollView(preferences: p)
let root = CalendarPopover(preferences: p, clock: clock, scroll: scroll, settings: {}, quit: {})
let host = NSHostingView(rootView: root)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 328, height: 480),
    styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = host
window.makeKeyAndOrderFront(nil)
host.layoutSubtreeIfNeeded()
settle()
scroll.open()
settle()
check(scroll.contentSize.width > 250, "Native scroll has a valid width")
check(scroll.contentSize.height > 300, "Native scroll has a valid height")
let current = p.engine.month(containing: Date()).start
check(scroll.calendarView.months.entries[scroll.calendarView.months.index(at: Double(scroll.contentView.bounds.minY))].month.start == current,
    "Open positions the native clip view on the current month")

for i in 0..<40 {
    let months = scroll.calendarView.months
    let entry = months.entries[i < 20 ? 110 : 10]
    scroll.contentView.scroll(to: NSPoint(x: 0, y: entry.y + 17.375))
    scroll.reflectScrolledClipView(scroll.contentView)
    settle()
    let adjusted = scroll.calendarView.months
    let index = adjusted.index(at: Double(scroll.contentView.bounds.minY))
    check(adjusted.entries[index].month.start == entry.month.start, "Native recenter preserves visible month")
    check(abs(Double(scroll.contentView.bounds.minY) - adjusted.entries[index].y - 17.375) < 0.001,
        "Native recenter preserves fractional pixel offset")
    check(adjusted.entries.count == 121, "Native month storage remains bounded")
}

scroll.goTo(Date(), animated: false)
settle()
for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
    window.appearance = NSAppearance(named: appearance)
    p.weekNumbers = true; p.textSize = 2
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
let visible = scroll.calendarView.months.entries[scroll.calendarView.months.index(at: Double(scroll.contentView.bounds.minY))]
check(p.engine.month(containing: p.lastMonth).start == visible.month.start, "Remembered month matches view")
print("PASS: native layout, today positioning, 40 bidirectional recentrings, fractional offsets, bounded storage, VoiceOver labels, light/dark rendering and position persistence.")
window.orderOut(nil)
