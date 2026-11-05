import Foundation
import Testing
@testable import InvoicingCore

@Suite struct CalendarDayTests {
    @Test func rejectsImpossibleDays() {
        #expect(CalendarDay(year: 2026, month: 2, day: 30) == nil)
        #expect(CalendarDay(year: 2026, month: 2, day: 29) == nil)
        #expect(CalendarDay(year: 2024, month: 2, day: 29) != nil)
        #expect(CalendarDay(year: 2026, month: 13, day: 1) == nil)
        #expect(CalendarDay(year: 2026, month: 4, day: 31) == nil)
        #expect(CalendarDay(year: 0, month: 1, day: 1) == nil)
    }

    @Test func parsesAndFormatsISO() throws {
        let parsed = try #require(CalendarDay(iso: "2026-11-04"))
        #expect(parsed.year == 2026)
        #expect(parsed.month == 11)
        #expect(parsed.day == 4)
        #expect(parsed.isoString == "2026-11-04")
        #expect(parsed.description == "2026-11-04")
        #expect(CalendarDay(iso: "2026-11") == nil)
        #expect(CalendarDay(iso: "04.11.2026") == nil)
        #expect(CalendarDay(iso: " 2026-01-05 ")?.day == 5)
        #expect(day("0999-01-01").isoString == "0999-01-01")
    }

    @Test func parsesAndFormatsCzech() {
        #expect(CalendarDay(czech: "04.11.2026") == day("2026-11-04"))
        #expect(CalendarDay(czech: "4.11.2026") == day("2026-11-04"))
        #expect(CalendarDay(czech: "4. 11. 2026") == day("2026-11-04"))
        #expect(CalendarDay(czech: "2026-11-04") == nil)
        #expect(CalendarDay(czech: "4. 11.") == nil)
        #expect(day("2026-11-04").czechString == "4. 11. 2026")
    }

    @Test func ordersAndCompares() {
        #expect(day("2026-11-04") < day("2026-11-05"))
        #expect(day("2026-12-31") < day("2027-01-01"))
        #expect(day("2026-01-31") < day("2026-02-01"))
        let sorted = [day("2026-03-01"), day("2025-12-31"), day("2026-01-15")].sorted()
        #expect(sorted == [day("2025-12-31"), day("2026-01-15"), day("2026-03-01")])
    }

    @Test func addsDaysAndMonths() {
        #expect(day("2026-11-05").adding(days: 30) == day("2026-12-05"))
        #expect(day("2026-11-05").adding(days: 60) == day("2027-01-04"))
        #expect(day("2026-11-05").adding(days: -5) == day("2026-10-31"))
        #expect(day("2026-01-31").adding(months: 1) == day("2026-02-28"))
        #expect(day("2024-01-31").adding(months: 1) == day("2024-02-29"))
        #expect(day("2026-11-05").adding(months: 2) == day("2027-01-05"))
    }

    @Test func monthBoundaries() {
        #expect(day("2026-02-10").startOfMonth == day("2026-02-01"))
        #expect(day("2026-02-10").endOfMonth == day("2026-02-28"))
        #expect(day("2024-02-10").endOfMonth == day("2024-02-29"))
        #expect(day("2026-12-05").endOfMonth == day("2026-12-31"))
    }

    @Test func countsDays() {
        #expect(day("2026-11-20").days(since: day("2026-11-05")) == 15)
        #expect(day("2027-01-01").days(since: day("2026-11-05")) == 57)
        #expect(day("2026-11-05").days(since: day("2026-11-20")) == -15)
    }

    @Test func weekdays() {
        #expect(day("2026-11-05").weekday == .thursday)
        #expect(day("2026-11-07").weekday == .saturday)
        #expect(day("2026-11-07").isWeekend)
        #expect(day("2026-11-08").isWeekend)
        #expect(!day("2026-11-09").isWeekend)
    }

    @Test func convertsToAndFromDates() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let west = try #require(TimeZone(secondsFromGMT: -8 * 3600))
        let prague = try #require(TimeZone(secondsFromGMT: 3600))
        let epoch = Date(timeIntervalSince1970: 0)
        #expect(CalendarDay(epoch, in: utc) == day("1970-01-01"))
        #expect(CalendarDay(epoch, in: west) == day("1969-12-31"))
        #expect(day("2026-11-05").midnight(in: utc) == Date(timeIntervalSince1970: 1_793_836_800))
        #expect(day("2026-11-05").midnight(in: prague) == Date(timeIntervalSince1970: 1_793_836_800 - 3600))
        #expect(CalendarDay(day("2026-11-05").midnight(in: prague), in: prague) == day("2026-11-05"))
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(day("2026-11-05"))
        let back = try JSONDecoder().decode(CalendarDay.self, from: data)
        #expect(back == day("2026-11-05"))
    }
}
