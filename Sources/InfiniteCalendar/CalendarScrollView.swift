import AppKit
import Combine
#if SWIFT_PACKAGE
import CalendarCore
#endif

final class CalendarViewport: ObservableObject {
    @Published var month = Date()
}

final class CalendarScrollView: NSScrollView {
    let viewport = CalendarViewport()
    private var viewportUpdatePending = false
    let calendarView: CalendarDocumentView
    private var observing: NSObjectProtocol?
    private var adjusting = false
    private var layoutKey = ""
    private let preferences: Preferences
    var onEscape: (() -> Void)?

    init(preferences: Preferences) {
        self.preferences = preferences
        calendarView = CalendarDocumentView(preferences: preferences)
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = false
        hasHorizontalScroller = false
        scrollerStyle = .overlay
        verticalScrollElasticity = .none
        horizontalScrollElasticity = .none
        autohidesScrollers = true
        documentView = calendarView
        contentView.postsBoundsChangedNotifications = true
        calendarView.onEscape = { [weak self] in self?.onEscape?() }
        observing = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: contentView, queue: .main) { [weak self] _ in self?.didScroll() }
        configure(force: true)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    deinit { if let observing { NotificationCenter.default.removeObserver(observing) } }

    override func layout() {
        super.layout()
        calendarView.setFrameSize(NSSize(width: contentSize.width, height: CGFloat(calendarView.weeks.totalHeight)))
        updateViewport()
    }

    func configure(force: Bool = false) {
        if force || layoutKey != preferences.layoutKey {
            let old = calendarView.weeks
            let i = old.index(at: contentView.bounds.minY)
            let week = old.entries[i].start
            let fraction = (contentView.bounds.minY - CGFloat(old.entries[i].y)) / CGFloat(old.rowHeight)
            calendarView.weeks = WeekWindow(center: week, engine: preferences.engine, rowHeight: Double(preferences.rowHeight))
            layoutKey = preferences.layoutKey
            adjusting = true
            calendarView.setFrameSize(NSSize(width: max(300, contentSize.width), height: CGFloat(calendarView.weeks.totalHeight)))
            contentView.scroll(to: NSPoint(x: 0, y: CGFloat(calendarView.weeks.offset(for: week) ?? 0) + fraction * preferences.rowHeight))
            reflectScrolledClipView(contentView)
            adjusting = false
        }
        calendarView.refreshFormatters()
        calendarView.needsDisplay = true
        updateViewport()
    }

    private func didScroll() {
        guard !adjusting else { return }
        if let origin = calendarView.weeks.recenter(origin: Double(contentView.bounds.minY)) {
            adjusting = true
            calendarView.setFrameSize(NSSize(width: contentSize.width, height: CGFloat(calendarView.weeks.totalHeight)))
            contentView.scroll(to: NSPoint(x: 0, y: CGFloat(origin)))
            reflectScrolledClipView(contentView)
            adjusting = false
        }
        calendarView.needsDisplay = true
        updateViewport(immediately: true)
    }

    private func refreshViewport() {
        let month = calendarView.weeks.visibleMonth(origin: Double(contentView.bounds.minY),
            viewportHeight: Double(contentSize.height))
        if viewport.month != month { viewport.month = month }
    }

    private func updateViewport(immediately: Bool = false) {
        if immediately { refreshViewport(); return }
        guard !viewportUpdatePending else { return }
        viewportUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewportUpdatePending = false
            self.refreshViewport()
        }
    }

    func open() {
        configure()
        if preferences.openToday { goTo(Date(), animated: false) }
        else { goTo(preferences.lastWeek, offset: preferences.lastOffset, animated: false, alignToMonth: false) }
        window?.makeFirstResponder(calendarView)
    }

    func remember() {
        let m = calendarView.weeks
        let i = m.index(at: Double(contentView.bounds.minY))
        preferences.remember(week: m.entries[i].start, offset: Double(contentView.bounds.minY) - m.entries[i].y)
    }

    func goTo(_ date: Date, offset: Double = 0, animated: Bool = true, alignToMonth: Bool = true) {
        let requestedDate = date
        let date = alignToMonth ? preferences.engine.month(containing: date).start : date
        calendarView.hoverTimer?.invalidate()
        calendarView.hovered = nil
        calendarView.focused = nil
        if calendarView.weeks.offset(for: date) == nil || calendarView.weeks.offset(for: requestedDate) == nil {
            adjusting = true
            calendarView.weeks.rebuild(center: date)
            calendarView.setFrameSize(NSSize(width: contentSize.width, height: CGFloat(calendarView.weeks.totalHeight)))
            adjusting = false
        }
        var origin = CGFloat(calendarView.weeks.offset(for: date) ?? 0) + CGFloat(offset)
        if alignToMonth, contentSize.height > 0, let dayRow = calendarView.weeks.offset(for: requestedDate) {
            // On a six-week month, Today must still reveal the actual current day
            // even when the compact viewport cannot fit the entire month.
            origin = max(origin, CGFloat(dayRow) + preferences.rowHeight - contentSize.height)
        }
        let target = NSPoint(x: 0, y: origin)
        let distance = abs(contentView.bounds.minY - target.y)
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && distance < 1200 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                contentView.animator().setBoundsOrigin(target)
            }
        } else { contentView.scroll(to: target) }
        reflectScrolledClipView(contentView)
        calendarView.needsDisplay = true
        updateViewport(immediately: true)
    }
}

final class CalendarDocumentView: NSView {
    var weeks: WeekWindow
    private let preferences: Preferences
    private let dayFormatter = DateFormatter()
    private let accessibilityFormatter = DateFormatter()
    var hovered: Date?
    private var previousHover: Date?
    private var hoverProgress: CGFloat = 1
    var hoverTimer: Timer?
    var focused: Date?
    var onEscape: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(preferences: Preferences) {
        self.preferences = preferences
        weeks = WeekWindow(center: Date(), engine: preferences.engine, rowHeight: Double(preferences.rowHeight))
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: CGFloat(weeks.totalHeight)))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        refreshFormatters()
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    deinit { hoverTimer?.invalidate() }

    func refreshFormatters() {
        for formatter in [dayFormatter, accessibilityFormatter] {
            formatter.locale = preferences.locale
            formatter.calendar = weeks.engine.calendar
            formatter.timeZone = weeks.engine.calendar.timeZone
        }
        dayFormatter.setLocalizedDateFormatFromTemplate("d")
        accessibilityFormatter.dateStyle = .full
        setAccessibilityLabel(preferences.text("Calendario. Frecce per i giorni, Pagina su e giù per scorrere, Home per oggi.",
            "Calendar. Arrow keys navigate days, Page Up and Down scroll, Home returns to today."))
    }

    private var leftInset: CGFloat { preferences.weekNumbers ? 40 : 16 }
    private var cellWidth: CGFloat { (bounds.width - leftInset - 16) / 7 }

    func cellFrame(entry: WeekWindow.Entry, day: Int) -> NSRect {
        NSRect(x: leftInset + CGFloat(day) * cellWidth, y: CGFloat(entry.y),
            width: cellWidth, height: preferences.rowHeight)
    }

    private func visibleEntries(in rect: NSRect) -> [WeekWindow.Entry] {
        let first = weeks.index(at: Double(rect.minY))
        let last = weeks.index(at: Double(rect.maxY))
        return Array(weeks.entries[first...last])
    }

    func dayColor(for date: Date, now: Date = Date()) -> NSColor {
        if weeks.engine.calendar.isDate(date, inSameDayAs: now) {
            return NSColor.hex(preferences.todayColor).contrastingText
        }
        if preferences.weekends && weeks.engine.calendar.isDateInWeekend(date)
            && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return NSColor.labelColor.withAlphaComponent(0.82)
        }
        return .labelColor
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, centered: Bool = true) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let h = font.ascender - font.descender + font.leading
        text.draw(in: NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h + 2), withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !dirtyRect.intersection(visibleRect).isEmpty else { return }
        let c = weeks.engine.calendar
        let now = Date()
        let weekFormatter = NumberFormatter()
        weekFormatter.locale = preferences.locale
        for e in visibleEntries(in: dirtyRect.intersection(visibleRect)) {
            if preferences.weekNumbers {
                let number = c.component(.weekOfYear, from: e.start)
                drawText(weekFormatter.string(from: NSNumber(value: number)) ?? String(number),
                    in: NSRect(x: 8, y: CGFloat(e.y), width: 26, height: preferences.rowHeight),
                    font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
            }
            for (i, date) in e.days.enumerated() {
                let rect = cellFrame(entry: e, day: i)
                guard rect.intersects(dirtyRect) else { continue }
                let today = c.isDate(date, inSameDayAs: now)
                let disk = NSRect(x: rect.midX - (preferences.rowHeight - 3) / 2,
                    y: rect.minY + 1.5, width: preferences.rowHeight - 3, height: preferences.rowHeight - 3)
                if today {
                    NSColor.hex(preferences.todayColor).setFill()
                    NSBezierPath(ovalIn: disk).fill()
                } else if preferences.hover {
                    let alpha: CGFloat = date == hovered ? hoverProgress : (date == previousHover ? 1 - hoverProgress : 0)
                    if alpha > 0 { NSColor.labelColor.withAlphaComponent(0.075 * alpha).setFill(); NSBezierPath(ovalIn: disk).fill() }
                }
                if let focused, c.isDate(date, inSameDayAs: focused) {
                    NSColor.hex(preferences.accent).setStroke()
                    let path = NSBezierPath(ovalIn: disk.insetBy(dx: -1, dy: -1)); path.lineWidth = 1.5; path.stroke()
                }
                let color = dayColor(for: date, now: now)
                drawText(dayFormatter.string(from: date), in: rect,
                    font: .monospacedDigitSystemFont(ofSize: preferences.fontSize, weight: today ? .semibold : .regular), color: color)
            }
        }
    }

    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    func date(at point: NSPoint) -> Date? {
        guard point.x >= leftInset, point.x < bounds.width - 16,
            point.y >= 0, point.y < bounds.height, cellWidth > 0 else { return nil }
        let entry = weeks.entries[weeks.index(at: Double(point.y))]
        let column = Int((point.x - leftInset) / cellWidth)
        return entry.days.indices.contains(column) ? entry.days[column] : nil
    }

    private func setHover(_ date: Date?) {
        guard preferences.hover, date != hovered else { return }
        hoverTimer?.invalidate()
        previousHover = hovered; hovered = date
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { hoverProgress = 1; needsDisplay = true; return }
        hoverProgress = 0
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.hoverProgress = min(1, CGFloat((ProcessInfo.processInfo.systemUptime - start) / 0.12))
            self.needsDisplay = true
            if self.hoverProgress >= 1 { timer.invalidate(); self.previousHover = nil }
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { setHover(date(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { setHover(nil) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        focused = date(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard let scroll = enclosingScrollView as? CalendarScrollView else { return }
        if event.keyCode == 53 { if preferences.escapeCloses { onEscape?() }; return }
        if event.keyCode == 115 { scroll.goTo(Date()); return }
        if event.keyCode == 116 || event.keyCode == 121 {
            let delta: CGFloat = event.keyCode == 116 ? -scroll.contentSize.height * 0.85 : scroll.contentSize.height * 0.85
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY + delta))
            scroll.reflectScrolledClipView(scroll.contentView)
            return
        }
        let amount: Int
        switch event.keyCode { case 123: amount = -1; case 124: amount = 1
        case 125: amount = 7; case 126: amount = -7; default: super.keyDown(with: event); return }
        let base = focused ?? weeks.entries[weeks.index(at: Double(visibleRect.minY))].start
        guard let next = weeks.engine.calendar.date(byAdding: .day, value: amount, to: base) else { return }
        if weeks.offset(for: next) == nil { scroll.goTo(next, animated: false, alignToMonth: false) }
        focused = next
        if let e = weeks.entries.first(where: { $0.start == weeks.engine.startOfWeek(containing: next) }),
           let i = e.days.firstIndex(where: { weeks.engine.calendar.isDate($0, inSameDayAs: next) }) {
            scrollToVisible(cellFrame(entry: e, day: i).insetBy(dx: 0, dy: -8))
        }
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
    }

    override func accessibilityChildren() -> [Any]? {
        var elements: [NSAccessibilityElement] = []
        for e in visibleEntries(in: visibleRect) {
            for (i, date) in e.days.enumerated() {
                let rect = cellFrame(entry: e, day: i)
                guard rect.intersects(visibleRect) else { continue }
                var label = accessibilityFormatter.string(from: date)
                if weeks.engine.calendar.isDateInToday(date) { label += preferences.text(", oggi", ", today") }
                let element = NSAccessibilityElement.element(withRole: .staticText, frame: .zero, label: label, parent: self) as! NSAccessibilityElement
                element.setAccessibilityFrameInParentSpace(rect)
                elements.append(element)
            }
        }
        return elements
    }
}
