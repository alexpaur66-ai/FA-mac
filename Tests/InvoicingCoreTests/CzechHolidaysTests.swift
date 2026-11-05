import Testing
@testable import InvoicingCore

@Suite struct CzechHolidaysTests {
    @Test func easterSunday() {
        #expect(CzechHolidays.easterSunday(year: 2024) == day("2024-03-31"))
        #expect(CzechHolidays.easterSunday(year: 2025) == day("2025-04-20"))
        #expect(CzechHolidays.easterSunday(year: 2026) == day("2026-04-05"))
        #expect(CzechHolidays.easterSunday(year: 2027) == day("2027-03-28"))
    }

    @Test func movableHolidays() {
        #expect(CzechHolidays.isHoliday(day("2026-04-03")))   // Velký pátek
        #expect(CzechHolidays.isHoliday(day("2026-04-06")))   // Velikonoční pondělí
        #expect(!CzechHolidays.isHoliday(day("2026-04-05")))  // Easter Sunday is not a listed holiday
        #expect(!CzechHolidays.isHoliday(day("2015-04-03")))  // Good Friday became a holiday in 2016
        #expect(CzechHolidays.isHoliday(day("2016-03-25")))
    }

    @Test func fixedHolidays() {
        for iso in ["2026-01-01", "2026-05-01", "2026-05-08", "2026-07-05", "2026-07-06", "2026-09-28",
                    "2026-10-28", "2026-11-17", "2026-12-24", "2026-12-25", "2026-12-26"] {
            #expect(CzechHolidays.isHoliday(day(iso)), "\(iso)")
        }
        #expect(!CzechHolidays.isHoliday(day("2026-11-05")))
        #expect(CzechHolidays.isWorkingDay(day("2026-11-05")))   // Thursday
        #expect(!CzechHolidays.isWorkingDay(day("2026-11-07")))  // Saturday
        #expect(!CzechHolidays.isWorkingDay(day("2026-11-17")))  // Tuesday, holiday
    }

    @Test func workingDayArithmetic() {
        #expect(CzechHolidays.lastWorkingDay(onOrBefore: day("2026-11-05")) == day("2026-11-05"))
        #expect(CzechHolidays.lastWorkingDay(onOrBefore: day("2026-10-31")) == day("2026-10-30"))  // Saturday → Friday
        #expect(CzechHolidays.lastWorkingDay(onOrBefore: day("2026-11-08")) == day("2026-11-06"))  // Sunday → Friday
        #expect(CzechHolidays.lastWorkingDay(onOrBefore: day("2026-10-28")) == day("2026-10-27"))  // holiday on a Wednesday
        #expect(CzechHolidays.lastWorkingDay(onOrBefore: day("2026-12-27")) == day("2026-12-23"))  // Christmas, then the weekend
        #expect(CzechHolidays.lastWorkingDay(onOrBefore: day("2026-05-02")) == day("2026-04-30"))  // Saturday after 1 May
        #expect(CzechHolidays.lastWorkingDay(onOrBefore: day("2026-04-06")) == day("2026-04-02"))  // Easter Monday
        #expect(CzechHolidays.previousWorkingDay(before: day("2026-11-09")) == day("2026-11-06"))
        #expect(CzechHolidays.nextWorkingDay(after: day("2026-04-02")) == day("2026-04-07"))
        #expect(CzechHolidays.nextWorkingDay(after: day("2026-11-05")) == day("2026-11-06"))
    }
}
