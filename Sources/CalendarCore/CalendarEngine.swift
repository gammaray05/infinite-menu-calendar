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

/// A bounded coordinate window. Rebuilding around the visible month preserves
/// its exact pixel offset; only the visible portion is drawn by the AppKit view.
public struct MonthWindow {
    public struct Entry {
        public let month: Month
        public let y: Double
        public let height: Double
    }
    public static let radius = 60
    public private(set) var entries: [Entry] = []
    public var totalHeight: Double { entries.last.map { $0.y + $0.height } ?? 0 }
    public var rowHeight: Double
    public let headerHeight: Double = 58
    public let bottomPadding: Double = 18
    public var engine: CalendarEngine

    public init(center: Date, engine: CalendarEngine, rowHeight: Double = 32) {
        self.engine = engine
        self.rowHeight = rowHeight
        rebuild(center: center)
    }

    public mutating func rebuild(center: Date) {
        entries.removeAll(keepingCapacity: true)
        var start = engine.addingMonths(-Self.radius, to: center)
        var y = 0.0
        for _ in 0...(Self.radius * 2) {
            let month = engine.month(containing: start)
            let height = headerHeight + Double(month.weeks) * rowHeight + bottomPadding
            entries.append(Entry(month: month, y: y, height: height))
            y += height
            start = engine.addingMonths(1, to: start)
        }
    }

    public func index(at y: Double) -> Int {
        // Binary search keeps fast wheel events independent of the months traversed.
        var low = 0, high = entries.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if entries[mid].y <= y { low = mid } else { high = mid - 1 }
        }
        return low
    }

    public func offset(for date: Date) -> Double? {
        let start = engine.month(containing: date).start
        return entries.first(where: { $0.month.start == start })?.y
    }

    /// Returns a compensated origin, or nil when no recentering is necessary.
    public mutating func recenter(origin: Double) -> Double? {
        let i = index(at: origin)
        guard i < 12 || i > entries.count - 13 else { return nil }
        let month = entries[i].month.start
        let intraMonth = origin - entries[i].y
        rebuild(center: month)
        return offset(for: month)! + intraMonth
    }
}
