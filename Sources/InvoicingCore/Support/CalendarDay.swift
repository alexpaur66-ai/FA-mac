import Foundation

/// A calendar date without a time or a time zone: the kind of date that appears on an
/// invoice (date of issue, date of taxable supply, due date). Gregorian calendar.
public struct CalendarDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns nil for a day that does not exist, for example 30 February.
    public init?(year: Int, month: Int, day: Int) {
        guard year > 0, (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Self.utcCalendar.date(from: components) else { return nil }
        let back = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day of `date` as seen in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 1
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    /// Parses ISO 8601 "2026-11-04". The year must have four digits; "26-11-04" is nil.
    public init?(iso text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              Self.isDigits(parts[0], count: 4...4), Self.isDigits(parts[1], count: 1...2), Self.isDigits(parts[2], count: 1...2),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Parses Czech notation: "04.11.2026", "4.11.2026" or "4. 11. 2026".
    /// The year must have four digits; "04.11.26" is nil rather than the year 26.
    public init?(czech text: String) {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              Self.isDigits(parts[0], count: 1...2), Self.isDigits(parts[1], count: 1...2), Self.isDigits(parts[2], count: 4...4),
              let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    // MARK: Formatting

    /// "2026-11-04"
    public var description: String { isoString }
    /// "2026-11-04"
    public var isoString: String { String(year).leftPadded(to: 4) + "-" + String(month).leftPadded(to: 2) + "-" + String(day).leftPadded(to: 2) }
    /// "4. 11. 2026", the notation used on Czech documents.
    public var czechString: String { "\(day). \(month). \(year)" }

    // MARK: Arithmetic

    public func adding(days: Int) -> CalendarDay {
        let date = Self.utcCalendar.date(byAdding: .day, value: days, to: utcDate) ?? utcDate
        return CalendarDay(date, in: Self.utc)
    }

    public func adding(months: Int) -> CalendarDay {
        let date = Self.utcCalendar.date(byAdding: .month, value: months, to: utcDate) ?? utcDate
        return CalendarDay(date, in: Self.utc)
    }

    public var startOfMonth: CalendarDay { CalendarDay(year: year, month: month, day: 1) ?? self }

    public var endOfMonth: CalendarDay {
        let range = Self.utcCalendar.range(of: .day, in: .month, for: utcDate)
        let last = range?.upperBound.advanced(by: -1) ?? day
        return CalendarDay(year: year, month: month, day: last) ?? self
    }

    /// Number of days from `other` to `self` (positive when `self` is later).
    public func days(since other: CalendarDay) -> Int {
        let components = Self.utcCalendar.dateComponents([.day], from: other.utcDate, to: utcDate)
        return components.day ?? 0
    }

    public enum Weekday: Int, Sendable {
        case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    }

    public var weekday: Weekday {
        Weekday(rawValue: Self.utcCalendar.component(.weekday, from: utcDate)) ?? .monday
    }

    public var isWeekend: Bool { weekday == .saturday || weekday == .sunday }

    /// Midnight at the start of this day in `timeZone`.
    public func midnight(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? utcDate
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: Private

    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()

    private var utcDate: Date {
        Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    /// ASCII digits only (no sign), with a length in `count`.
    private static func isDigits(_ text: Substring, count: ClosedRange<Int>) -> Bool {
        count.contains(text.count) && text.allSatisfy(\.isASCIIDigit)
    }
}

/// Stored as {"year":2026,"month":11,"day":5}. Decoding validates like `init?(year:month:day:)`,
/// so an impossible day such as 30 February throws instead of drifting to another date.
extension CalendarDay: Codable {
    private enum CodingKeys: String, CodingKey { case year, month, day }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let y = try container.decode(Int.self, forKey: .year)
        let m = try container.decode(Int.self, forKey: .month)
        let d = try container.decode(Int.self, forKey: .day)
        guard let value = CalendarDay(year: y, month: m, day: d) else {
            throw DecodingError.dataCorruptedError(forKey: .day, in: container, debugDescription: "Invalid calendar day \(y)-\(m)-\(d)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(day, forKey: .day)
    }
}
