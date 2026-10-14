import AppKit
#if SWIFT_PACKAGE
import CalendarCore
#endif

final class CalendarScrollView: NSScrollView {
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
        hasVerticalScroller = true
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
        calendarView.setFrameSize(NSSize(width: contentSize.width, height: CGFloat(calendarView.months.totalHeight)))
    }

    func configure(force: Bool = false) {
        if force || layoutKey != preferences.layoutKey {
            let old = calendarView.months
            let i = old.index(at: contentView.bounds.minY)
            let month = old.entries[i].month.start
            let delta = contentView.bounds.minY - CGFloat(old.entries[i].y)
            calendarView.months = MonthWindow(center: month, engine: preferences.engine, rowHeight: Double(preferences.rowHeight))
            layoutKey = preferences.layoutKey
            adjusting = true
            calendarView.setFrameSize(NSSize(width: max(300, contentSize.width), height: CGFloat(calendarView.months.totalHeight)))
            contentView.scroll(to: NSPoint(x: 0, y: CGFloat(calendarView.months.offset(for: month) ?? 0) + delta))
            reflectScrolledClipView(contentView)
            adjusting = false
        }
        calendarView.refreshFormatters()
        calendarView.needsDisplay = true
    }

    private func didScroll() {
        guard !adjusting else { return }
        if let origin = calendarView.months.recenter(origin: Double(contentView.bounds.minY)) {
            adjusting = true
            calendarView.setFrameSize(NSSize(width: contentSize.width, height: CGFloat(calendarView.months.totalHeight)))
            contentView.scroll(to: NSPoint(x: 0, y: CGFloat(origin)))
            reflectScrolledClipView(contentView)
            adjusting = false
        }
        calendarView.needsDisplay = true
    }

    func open() {
        configure()
        if preferences.openToday { goTo(Date(), animated: false) }
        else { goTo(preferences.lastMonth, offset: preferences.lastOffset, animated: false) }
        window?.makeFirstResponder(calendarView)
    }

    func remember() {
        let m = calendarView.months
        let i = m.index(at: Double(contentView.bounds.minY))
        preferences.remember(month: m.entries[i].month.start, offset: Double(contentView.bounds.minY) - m.entries[i].y)
    }

    func goTo(_ date: Date, offset: Double = 0, animated: Bool = true) {
        calendarView.hoverTimer?.invalidate()
        calendarView.hovered = nil
        calendarView.focused = nil
        if calendarView.months.offset(for: date) == nil {
            adjusting = true
            calendarView.months.rebuild(center: date)
            calendarView.setFrameSize(NSSize(width: contentSize.width, height: CGFloat(calendarView.months.totalHeight)))
            adjusting = false
        }
        let target = NSPoint(x: 0, y: CGFloat(calendarView.months.offset(for: date) ?? 0) + CGFloat(offset))
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
    }
}

final class CalendarDocumentView: NSView {
    var months: MonthWindow
    private let preferences: Preferences
    private let monthFormatter = DateFormatter()
    private let dayFormatter = DateFormatter()
    private let accessibilityFormatter = DateFormatter()
    private var weekdays: [String] = []
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
        months = MonthWindow(center: Date(), engine: preferences.engine, rowHeight: Double(preferences.rowHeight))
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: CGFloat(months.totalHeight)))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        refreshFormatters()
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    deinit { hoverTimer?.invalidate() }

    func refreshFormatters() {
        for formatter in [monthFormatter, dayFormatter, accessibilityFormatter] {
            formatter.locale = preferences.locale
            formatter.calendar = months.engine.calendar
            formatter.timeZone = months.engine.calendar.timeZone
        }
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        dayFormatter.setLocalizedDateFormatFromTemplate("d")
        accessibilityFormatter.dateStyle = .full
        weekdays = monthFormatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        setAccessibilityLabel(preferences.text("Calendario. Frecce per i giorni, Pagina su e giù per scorrere, Home per oggi.",
            "Calendar. Arrow keys navigate days, Page Up and Down scroll, Home returns to today."))
    }

    private var leftInset: CGFloat { preferences.weekNumbers ? 40 : 16 }
    private var cellWidth: CGFloat { (bounds.width - leftInset - 16) / 7 }

    private func cellFrame(entry: MonthWindow.Entry, day: Int) -> NSRect {
        let cell = entry.month.leadingDays + day
        return NSRect(x: leftInset + CGFloat(cell % 7) * cellWidth,
            y: CGFloat(entry.y + months.headerHeight) + CGFloat(cell / 7) * preferences.rowHeight,
            width: cellWidth, height: preferences.rowHeight)
    }

    private func visibleEntries(in rect: NSRect) -> [MonthWindow.Entry] {
        let first = months.index(at: Double(rect.minY))
        let last = months.index(at: Double(rect.maxY))
        return Array(months.entries[first...last])
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, centered: Bool = true) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let h = font.ascender - font.descender + font.leading
        text.draw(in: NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h + 2), withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = months.engine.calendar
        let now = Date()
        for e in visibleEntries(in: dirtyRect.intersection(visibleRect)) {
            drawText(monthFormatter.string(from: e.month.start),
                in: NSRect(x: 18, y: CGFloat(e.y) + 2, width: bounds.width - 36, height: 30),
                font: .systemFont(ofSize: preferences.fontSize, weight: .semibold), color: .labelColor, centered: false)
            for column in 0..<7 {
                let weekday = (c.firstWeekday - 1 + column) % 7
                drawText(weekdays[weekday], in: NSRect(x: leftInset + CGFloat(column) * cellWidth,
                    y: CGFloat(e.y) + 33, width: cellWidth, height: 21),
                    font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
            }
            if preferences.weekNumbers {
                for row in 0..<e.month.weeks {
                    let number = c.component(.weekOfYear, from: months.engine.weekStart(in: e.month, row: row))
                    let formatter = NumberFormatter(); formatter.locale = preferences.locale
                    drawText(formatter.string(from: NSNumber(value: number)) ?? String(number),
                        in: NSRect(x: 8, y: CGFloat(e.y + months.headerHeight) + CGFloat(row) * preferences.rowHeight,
                            width: 26, height: preferences.rowHeight), font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
                }
            }
            for (i, date) in e.month.days.enumerated() {
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
                let color: NSColor = today ? NSColor.hex(preferences.todayColor).contrastingText
                    : (preferences.weekends && c.isDateInWeekend(date) ? .secondaryLabelColor : .labelColor)
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

    private func date(at point: NSPoint) -> Date? {
        let e = months.entries[months.index(at: Double(point.y))]
        guard point.x >= leftInset, point.x < bounds.width - 16,
            point.y >= CGFloat(e.y + months.headerHeight) else { return nil }
        let row = Int((point.y - CGFloat(e.y + months.headerHeight)) / preferences.rowHeight)
        let column = Int((point.x - leftInset) / cellWidth)
        let index = row * 7 + column - e.month.leadingDays
        return e.month.days.indices.contains(index) ? e.month.days[index] : nil
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
        let base = focused ?? months.entries[months.index(at: Double(visibleRect.minY))].month.start
        guard let next = months.engine.calendar.date(byAdding: .day, value: amount, to: base) else { return }
        if months.offset(for: next) == nil { scroll.goTo(next, animated: false) }
        focused = next
        if let e = months.entries.first(where: { $0.month.start == months.engine.month(containing: next).start }),
           let i = e.month.days.firstIndex(where: { months.engine.calendar.isDate($0, inSameDayAs: next) }) {
            scrollToVisible(cellFrame(entry: e, day: i).insetBy(dx: 0, dy: -8))
        }
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
    }

    override func accessibilityChildren() -> [Any]? {
        var elements: [NSAccessibilityElement] = []
        for e in visibleEntries(in: visibleRect) {
            let header = NSAccessibilityElement.element(withRole: .staticText, frame: .zero,
                label: monthFormatter.string(from: e.month.start), parent: self)
            header.setAccessibilityFrameInParentSpace(NSRect(x: 18, y: CGFloat(e.y), width: bounds.width - 36, height: 30))
            elements.append(header)
            for (i, date) in e.month.days.enumerated() {
                let rect = cellFrame(entry: e, day: i)
                guard rect.intersects(visibleRect) else { continue }
                var label = accessibilityFormatter.string(from: date)
                if months.engine.calendar.isDateInToday(date) { label += preferences.text(", oggi", ", today") }
                let element = NSAccessibilityElement.element(withRole: .staticText, frame: .zero, label: label, parent: self)
                element.setAccessibilityFrameInParentSpace(rect)
                elements.append(element)
            }
        }
        return elements
    }
}
