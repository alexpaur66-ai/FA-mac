/// A numbering series: one per document type (invoice, advance request, payment-receipt tax
/// document). Issues continuous numbers and restarts the counter each year when `resetsYearly`.
public struct DocumentNumberSeries: Hashable, Sendable, Codable {
    public enum NumberingError: Error, Equatable, Sendable {
        /// The document is dated in a year before the series' current year; the earlier year's series is closed.
        case dayBeforeSeriesYear(CalendarDay, seriesYear: Int)
    }

    /// Identifier of the series, e.g. "invoice", "advance", "paymentReceipt".
    public let id: String
    public let pattern: DocumentNumberPattern
    public let resetsYearly: Bool
    public private(set) var year: Int
    /// Last issued counter; 0 when nothing has been issued in `year`.
    public private(set) var lastCounter: Int

    public init(id: String, pattern: DocumentNumberPattern, resetsYearly: Bool = true, year: Int, lastCounter: Int = 0) {
        self.id = id
        self.pattern = pattern
        self.resetsYearly = resetsYearly
        self.year = year
        self.lastCounter = lastCounter
    }

    /// The number the next document dated `day` would get, without issuing it.
    public func peek(on day: CalendarDay) throws -> String {
        var copy = self
        return try copy.next(on: day)
    }

    /// Issues the next number for a document dated `day`.
    public mutating func next(on day: CalendarDay) throws -> String {
        if resetsYearly {
            if day.year < year { throw NumberingError.dayBeforeSeriesYear(day, seriesYear: year) }
            if day.year > year {
                year = day.year
                lastCounter = 0
            }
        }
        lastCounter += 1
        return pattern.format(year: resetsYearly ? year : day.year, counter: lastCounter)
    }

    /// The last issued number, or nil when none was issued in the current year.
    public var lastNumber: String? {
        lastCounter > 0 ? pattern.format(year: year, counter: lastCounter) : nil
    }
}
