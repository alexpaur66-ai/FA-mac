/// A numbering series: one per document type (invoice, advance request, payment-receipt tax
/// document). Issues continuous numbers and restarts the counter each year when `resetsYearly`.
public struct DocumentNumberSeries: Hashable, Sendable {
    public enum NumberingError: Error, Equatable, Sendable {
        /// The document is dated in a year before the series' current year; the earlier year's series is closed.
        case dayBeforeSeriesYear(CalendarDay, seriesYear: Int)
        /// A series that restarts its counter every year needs `{YYYY}` or `{YY}` in its pattern,
        /// otherwise each year would issue the same numbers again (§ 29 odst. 1 písm. e) ZDPH).
        case resettingSeriesRequiresYearInPattern
        /// The year is below 1 or the counter is negative; no series can reach that state.
        case invalidState(year: Int, lastCounter: Int)
        /// The variable symbol prefix must be 1 to 3 digits and must not start with 0, which banks ignore.
        case invalidVariableSymbolPrefix(String)
    }

    /// Identifier of the series, e.g. "invoice", "advance", "paymentReceipt".
    public let id: String
    public let pattern: DocumentNumberPattern
    public let resetsYearly: Bool
    public private(set) var year: Int
    /// Last issued counter; 0 when nothing has been issued in `year`.
    public private(set) var lastCounter: Int
    /// The year the last issued number was formatted with; nil when unknown, then `year` is used.
    /// Differs from `year` only for a series that does not reset yearly.
    public private(set) var lastIssuedYear: Int?
    /// Digits put in front of the number's digits in the variable symbol (ADR 0003 addendum), so that two
    /// series with the same template never give two documents of a year the same symbol. Nil: the symbol
    /// is the number's digits alone. 1 to 3 digits, not starting with 0.
    public let variableSymbolPrefix: String?

    /// Throws when a yearly-resetting pattern has no year token, the year or counter is out of range, or
    /// the variable symbol prefix is not 1 to 3 digits (an empty or blank prefix counts as none).
    public init(id: String, pattern: DocumentNumberPattern, resetsYearly: Bool = true, year: Int, lastCounter: Int = 0, lastIssuedYear: Int? = nil,
                variableSymbolPrefix: String? = nil) throws {
        guard year >= 1, lastCounter >= 0, (lastIssuedYear ?? 1) >= 1 else {
            throw NumberingError.invalidState(year: year, lastCounter: lastCounter)
        }
        guard !resetsYearly || pattern.containsYear else { throw NumberingError.resettingSeriesRequiresYearInPattern }
        let prefix = variableSymbolPrefix?.trimmingWhitespace() ?? ""
        if prefix.isEmpty {
            self.variableSymbolPrefix = nil
        } else {
            guard prefix.count <= 3, prefix.allSatisfy(\.isASCIIDigit), prefix.first != "0" else {
                throw NumberingError.invalidVariableSymbolPrefix(prefix)
            }
            self.variableSymbolPrefix = prefix
        }
        self.id = id
        self.pattern = pattern
        self.resetsYearly = resetsYearly
        self.year = year
        self.lastCounter = lastCounter
        self.lastIssuedYear = lastIssuedYear
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
        let formatYear = resetsYearly ? year : day.year
        lastIssuedYear = formatYear
        return pattern.format(year: formatYear, counter: lastCounter)
    }

    /// The last issued number exactly as it was issued, or nil when none was issued
    /// (for a yearly-resetting series: none in the current year).
    public var lastNumber: String? {
        lastCounter > 0 ? pattern.format(year: lastIssuedYear ?? year, counter: lastCounter) : nil
    }
}

/// Decoding runs the same checks as the initializer, so a corrupted or hand-edited stored series
/// (negative counter, year-less pattern for a resetting series) throws instead of issuing numbers.
extension DocumentNumberSeries: Codable {
    private enum CodingKeys: String, CodingKey { case id, pattern, resetsYearly, year, lastCounter, lastIssuedYear, variableSymbolPrefix }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let pattern = try container.decode(DocumentNumberPattern.self, forKey: .pattern)
        let resetsYearly = try container.decode(Bool.self, forKey: .resetsYearly)
        let year = try container.decode(Int.self, forKey: .year)
        let lastCounter = try container.decode(Int.self, forKey: .lastCounter)
        let lastIssuedYear = try container.decodeIfPresent(Int.self, forKey: .lastIssuedYear)
        let prefix = try container.decodeIfPresent(String.self, forKey: .variableSymbolPrefix)
        do {
            try self.init(id: id, pattern: pattern, resetsYearly: resetsYearly, year: year, lastCounter: lastCounter, lastIssuedYear: lastIssuedYear,
                          variableSymbolPrefix: prefix)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .lastCounter, in: container, debugDescription: "Invalid numbering series \(id): \(error)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(resetsYearly, forKey: .resetsYearly)
        try container.encode(year, forKey: .year)
        try container.encode(lastCounter, forKey: .lastCounter)
        try container.encodeIfPresent(lastIssuedYear, forKey: .lastIssuedYear)
        try container.encodeIfPresent(variableSymbolPrefix, forKey: .variableSymbolPrefix)
    }
}
