/// Czech public holidays (zákon č. 245/2000 Sb., o státních svátcích) and the working-day arithmetic
/// the exchange-rate lookup needs: the ČNB publishes no rate on weekends and holidays, so the rate
/// valid for such a day is the one published on the last working day before it.
public enum CzechHolidays {
    /// Fixed-date holidays as (month, day).
    private static let fixed: [(month: Int, day: Int)] = [
        (1, 1),    // Den obnovy samostatného českého státu; Nový rok
        (5, 1),    // Svátek práce
        (5, 8),    // Den vítězství
        (7, 5),    // Den slovanských věrozvěstů Cyrila a Metoděje
        (7, 6),    // Den upálení mistra Jana Husa
        (9, 28),   // Den české státnosti
        (10, 28),  // Den vzniku samostatného československého státu
        (11, 17),  // Den boje za svobodu a demokracii
        (12, 24),  // Štědrý den
        (12, 25),  // 1. svátek vánoční
        (12, 26),  // 2. svátek vánoční
    ]

    public static func isHoliday(_ day: CalendarDay) -> Bool {
        if fixed.contains(where: { $0.month == day.month && $0.day == day.day }) { return true }
        guard let easter = easterSunday(year: day.year) else { return false }
        if day == easter.adding(days: 1) { return true }                      // Velikonoční pondělí
        if day.year >= 2016, day == easter.adding(days: -2) { return true }   // Velký pátek, a holiday since 2016
        return false
    }

    public static func isWorkingDay(_ day: CalendarDay) -> Bool {
        !day.isWeekend && !isHoliday(day)
    }

    /// The last working day on or before `day`: `day` itself when it is one.
    public static func lastWorkingDay(onOrBefore day: CalendarDay) -> CalendarDay {
        var candidate = day
        for _ in 0..<14 {
            if isWorkingDay(candidate) { return candidate }
            candidate = candidate.adding(days: -1)
        }
        return candidate
    }

    /// The first working day after `day`.
    public static func nextWorkingDay(after day: CalendarDay) -> CalendarDay {
        var candidate = day.adding(days: 1)
        for _ in 0..<14 {
            if isWorkingDay(candidate) { return candidate }
            candidate = candidate.adding(days: 1)
        }
        return candidate
    }

    /// The last working day strictly before `day`.
    public static func previousWorkingDay(before day: CalendarDay) -> CalendarDay {
        lastWorkingDay(onOrBefore: day.adding(days: -1))
    }

    /// Easter Sunday in the Gregorian calendar (Meeus/Jones/Butcher algorithm).
    public static func easterSunday(year: Int) -> CalendarDay? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return CalendarDay(year: year, month: month, day: day)
    }
}
