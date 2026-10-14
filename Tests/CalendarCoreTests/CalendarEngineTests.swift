import XCTest
@testable import CalendarCore

final class CalendarEngineTests: XCTestCase {
    private func engine(_ identifier: Calendar.Identifier = .gregorian, zone: String = "Europe/Rome", first: Int = 2) -> CalendarEngine {
        var c = Calendar(identifier: identifier)
        c.timeZone = TimeZone(identifier: zone)!
        c.locale = Locale(identifier: "it_IT")
        c.firstWeekday = first
        return CalendarEngine(calendar: c)
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, engine: CalendarEngine) -> Date {
        engine.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testLeapYearsAndCenturyRules() {
        let e = engine()
        for (year, count) in [(1900, 28), (2000, 29), (2024, 29), (2026, 28), (2100, 28)] {
            XCTAssertEqual(e.month(containing: date(year, 2, 10, engine: e)).days.count, count)
        }
    }
    func testWeekAlignmentAndVariableRows() {
        let monday = engine(); let sunday = engine(first: 1)
        let february = date(2021, 2, 1, engine: monday)
        XCTAssertEqual(monday.month(containing: february).leadingDays, 0)
        XCTAssertEqual(monday.month(containing: february).weeks, 4)
        XCTAssertEqual(sunday.month(containing: february).leadingDays, 1)
        XCTAssertEqual(sunday.month(containing: february).weeks, 5)
        XCTAssertEqual(monday.month(containing: date(2026, 3, 1, engine: monday)).weeks, 6)
    }
    func testDSTAndTimeZones() {
        for zone in ["Europe/Rome", "America/New_York", "Pacific/Auckland", "Asia/Kathmandu"] {
            let e = engine(zone: zone)
            for month in [3, 10, 11] {
                let m = e.month(containing: date(2026, month, 10, engine: e))
                let count = e.calendar.range(of: .day, in: .month, for: m.start)!.count
                XCTAssertEqual(m.days.count, count)
                XCTAssertEqual(Set(m.days.map { e.calendar.component(.day, from: $0) }).count, count)
                for pair in zip(m.days, m.days.dropFirst()) {
                    XCTAssertEqual(e.calendar.dateComponents([.day], from: pair.0, to: pair.1).day, 1)
                }
            }
        }
    }
    func testYearBoundaryAndNonGregorianCalendars() {
        let gregorian = engine()
        let december = date(2026, 12, 1, engine: gregorian)
        let january = gregorian.addingMonths(1, to: december)
        XCTAssertEqual(gregorian.calendar.component(.year, from: january), 2027)
        XCTAssertEqual(gregorian.calendar.component(.month, from: january), 1)
        for identifier: Calendar.Identifier in [.gregorian, .hebrew, .islamicCivil, .buddhist, .japanese] {
            let e = engine(identifier)
            var current = e.month(containing: Date()).start
            for _ in 0..<180 {
                let m = e.month(containing: current)
                XCTAssertTrue((28...31).contains(m.days.count))
                XCTAssertTrue((4...6).contains(m.weeks))
                let next = e.addingMonths(1, to: current)
                XCTAssertEqual(e.calendar.dateInterval(of: .month, for: current)!.end, next)
                XCTAssertEqual(e.addingMonths(-1, to: next), current)
                current = next
            }
        }
    }
    func testThousandsOfRecenteringsPreserveExactOffsetAndBoundedStorage() {
        let e = engine()
        var w = WeekWindow(center: Date(), engine: e)
        for iteration in 0..<1000 {
            let i = iteration < 500 ? 300 : 10
            let entry = w.entries[i]
            let delta = 17.375
            let compensated = w.recenter(origin: entry.y + delta)
            XCTAssertNotNil(compensated)
            XCTAssertEqual(compensated!, w.offset(for: entry.start)! + delta, accuracy: 0.00001)
            XCTAssertEqual(w.entries.count, 313)
            XCTAssertEqual(w.entries[w.index(at: compensated!)].start, entry.start)
        }
    }
    func testFastScrollCrossingMonthBoundaries() {
        var w = WeekWindow(center: Date(), engine: engine())
        var origin = w.entries[156].y
        for delta in [125.0, 3000, 9000, -8000, -9500, 2000] {
            origin = max(0, min(w.totalHeight - 600, origin + delta))
            let visible = w.entries[w.index(at: origin)]
            let within = origin - visible.y
            if let new = w.recenter(origin: origin) { origin = new }
            XCTAssertEqual(w.entries[w.index(at: origin)].start, visible.start)
            XCTAssertEqual(origin - w.entries[w.index(at: origin)].y, within, accuracy: 0.00001)
        }
    }
    func testContinuousWeeksHaveNoGapsDuplicatesOrMonthPadding() {
        for first in [1, 2] {
            for zone in ["Europe/Rome", "America/New_York", "Pacific/Auckland"] {
                for identifier: Calendar.Identifier in [.gregorian, .hebrew, .islamicCivil, .buddhist, .japanese] {
                    let e = engine(identifier, zone: zone, first: first)
                    let w = WeekWindow(center: Date(), engine: e)
                    let days = w.entries.flatMap(\.days)
                    XCTAssertEqual(Set(days).count, days.count)
                    for (i, row) in w.entries.enumerated() {
                        XCTAssertEqual(row.days.count, 7)
                        XCTAssertEqual(e.calendar.component(.weekday, from: row.start), first)
                        XCTAssertEqual(row.y, Double(i) * w.rowHeight)
                    }
                    for pair in zip(days, days.dropFirst()) {
                        XCTAssertEqual(e.calendar.date(byAdding: .day, value: 1, to: pair.0), pair.1)
                    }
                }
            }
        }
    }

    func testContinuousWeekAcrossYearAndLeapDay() {
        let e = engine()
        for center in [date(2026, 12, 31, engine: e), date(2024, 2, 29, engine: e)] {
            let w = WeekWindow(center: center, engine: e)
            let row = w.entries[w.index(at: w.offset(for: center)!)]
            XCTAssertTrue(row.days.contains(where: { e.calendar.isDate($0, inSameDayAs: center) }))
            let nextWeek = w.entries[w.index(at: w.offset(for: center)!) + 1]
            XCTAssertEqual(e.calendar.date(byAdding: .day, value: 1, to: row.days[6]), nextWeek.days[0])
        }
    }

    func testPinnedMonthFollowsViewportAndTodayStartsAtMonthWeek() {
        let e = engine()
        for month in 1...12 {
            let start = date(2026, month, 1, engine: e)
            let w = WeekWindow(center: start, engine: e)
            let origin = w.offset(for: start)!
            XCTAssertEqual(w.visibleMonth(origin: origin, viewportHeight: 160), e.month(containing: start).start)
            let future = e.addingMonths(1, to: start)
            XCTAssertEqual(w.visibleMonth(origin: w.offset(for: future)!, viewportHeight: 160), e.month(containing: future).start)
        }
    }

}
