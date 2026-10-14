import Foundation

public struct Month: Equatable {
    public let start: Date
    public let days: [Date]
    public let leadingDays: Int
    public var weeks: Int { (leadingDays + days.count + 6) / 7 }
}

public struct CalendarEngine {
    public var calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    public func month(containing date: Date) -> Month {
        let interval = calendar.dateInterval(of: .month, for: date)!
        var days: [Date] = []
        var day = interval.start
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        return Month(start: interval.start, days: days, leadingDays: leading)
    }

    public func addingMonths(_ amount: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: amount, to: month(containing: date).start)!
    }

    public func weekStart(in month: Month, row: Int) -> Date {
        calendar.date(byAdding: .day, value: row * 7 - month.leadingDays, to: month.start)!
    }
}

/// A continuous, bounded sequence of weeks. Every date appears exactly once;
/// crossing a month never inserts padding, an empty cell or a duplicate week.
public struct WeekWindow {
    public struct Entry {
        public let start: Date
        public let days: [Date]
        public let y: Double
    }
    public static let radius = 156
    public private(set) var entries: [Entry] = []
    public var totalHeight: Double { Double(entries.count) * rowHeight }
    public var rowHeight: Double
    public var engine: CalendarEngine

    public init(center: Date, engine: CalendarEngine, rowHeight: Double = 32) {
        self.engine = engine
        self.rowHeight = rowHeight
        rebuild(center: center)
    }

    public mutating func rebuild(center: Date) {
        entries.removeAll(keepingCapacity: true)
        let first = engine.calendar.date(byAdding: .day, value: -Self.radius * 7,
            to: engine.startOfWeek(containing: center))!
        var start = first
        for i in 0...(Self.radius * 2) {
            let days = (0..<7).map { engine.calendar.date(byAdding: .day, value: $0, to: start)! }
            entries.append(Entry(start: start, days: days, y: Double(i) * rowHeight))
            start = engine.calendar.date(byAdding: .day, value: 7, to: start)!
        }
    }

    public func index(at y: Double) -> Int {
        guard y.isFinite else { return y == .infinity ? entries.count - 1 : 0 }
        let row = floor(y / rowHeight)
        if row <= 0 { return 0 }
        if row >= Double(entries.count - 1) { return entries.count - 1 }
        return Int(row)
    }

    public func offset(for date: Date) -> Double? {
        let start = engine.startOfWeek(containing: date)
        return entries.first(where: { $0.start == start })?.y
    }

    public mutating func recenter(origin: Double) -> Double? {
        let i = index(at: origin)
        guard i < 26 || i > entries.count - 27 else { return nil }
        let week = entries[i].start
        let withinRow = origin - entries[i].y
        rebuild(center: week)
        return offset(for: week)! + withinRow
    }

    /// The month occupying the middle of the visible grid drives the fixed title.
    public func visibleMonth(origin: Double, viewportHeight: Double) -> Date {
        let row = entries[index(at: origin + viewportHeight / 2)]
        return engine.month(containing: row.days[3]).start
    }
}

extension CalendarEngine {
    public func startOfWeek(containing date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let leading = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -leading, to: day)!
    }
}
