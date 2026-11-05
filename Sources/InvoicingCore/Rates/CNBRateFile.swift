import Foundation

/// Parsers for the ČNB exchange-rate text files ("kurzy devizového trhu").
///
/// Daily file (`denni_kurz.txt?date=DD.MM.YYYY`):
/// ```
/// 04.11.2026 #212
/// země|měna|množství|kód|kurz
/// EMU|euro|1|EUR|24,310
/// ```
/// Yearly file (`rok.txt?rok=YYYY`):
/// ```
/// Datum|1 AUD|1 BRL|...|1 EUR|...
/// 02.01.2026|13,797|3,789|...|24,170|...
/// ```
/// The English versions use "Date", a dot as decimal separator and "03.Jan.2000" in the daily
/// header; both are accepted. Weekends and holidays have no rows. Verified against the live
/// files on 5 Nov 2026 (see docs/compliance-checklist.md for the source list).
public enum CNBRateFile {
    public struct DailyFile: Hashable, Sendable {
        public let day: CalendarDay
        /// ČNB sequence number of the day ("#212").
        public let order: Int?
        public let rates: [ExchangeRate]
    }

    public enum ParseError: Error, Equatable, Sendable {
        case empty
        case malformedHeader(String)
        case malformedLine(lineNumber: Int, text: String)
        case unknownDate(String)
    }

    /// Parses a daily file. Rows with an unparsable, zero or negative rate are skipped; a malformed header throws.
    public static func parseDaily(_ text: String) throws -> DailyFile {
        let lines = Self.lines(of: text)
        guard lines.count >= 2 else { throw ParseError.empty }

        let header = lines[0]
        let headerParts = header.split(separator: "#", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let dateText = headerParts.first, let day = Self.parseDate(dateText) else {
            throw ParseError.malformedHeader(header)
        }
        let order = headerParts.count > 1 ? Int(headerParts[1]) : nil

        var rates: [ExchangeRate] = []
        for (index, line) in lines.dropFirst(2).enumerated() {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard cells.count == 5 else { throw ParseError.malformedLine(lineNumber: index + 3, text: line) }
            guard let amount = Int(cells[2].trimmingCharacters(in: .whitespaces)), amount > 0,
                  let rate = Decimal(lenient: cells[4]), rate > 0 else { continue }
            let code = cells[3].trimmingCharacters(in: .whitespaces)
            guard code.count == 3 else { continue }
            rates.append(ExchangeRate(currency: Currency.known(code), amount: amount, czkPerAmount: rate, validFor: day, source: .cnb(order: order)))
        }
        return DailyFile(day: day, order: order, rates: rates)
    }

    /// Parses a yearly file into rates for every currency and every published day.
    /// Cells with an unparsable, zero or negative rate are skipped.
    public static func parseYearly(_ text: String) throws -> [ExchangeRate] {
        let lines = Self.lines(of: text)
        guard let header = lines.first else { throw ParseError.empty }

        let columns = header.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard columns.count >= 2, ["Datum", "Date"].contains(columns[0]) else { throw ParseError.malformedHeader(header) }

        struct Column { let amount: Int; let currency: Currency }
        var parsedColumns: [Column?] = []
        for column in columns.dropFirst() {
            let parts = column.split(separator: " ")
            if parts.count == 2, let amount = Int(parts[0]), amount > 0, parts[1].count == 3 {
                parsedColumns.append(Column(amount: amount, currency: Currency.known(String(parts[1]))))
            } else {
                parsedColumns.append(nil)
            }
        }
        guard parsedColumns.contains(where: { $0 != nil }) else { throw ParseError.malformedHeader(header) }

        var rates: [ExchangeRate] = []
        for (index, line) in lines.dropFirst().enumerated() {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard cells.count == columns.count else { throw ParseError.malformedLine(lineNumber: index + 2, text: line) }
            guard let day = Self.parseDate(cells[0]) else { throw ParseError.unknownDate(cells[0]) }
            for (cell, column) in zip(cells.dropFirst(), parsedColumns) {
                guard let column, let rate = Decimal(lenient: cell), rate > 0 else { continue }
                rates.append(ExchangeRate(currency: column.currency, amount: column.amount, czkPerAmount: rate, validFor: day, source: .cnb(order: nil)))
            }
        }
        return rates
    }

    // MARK: Helpers

    /// Trimmed, non-empty lines; a UTF-8 byte order mark at the start (added by some editors) is ignored.
    private static func lines(of text: String) -> [String] {
        var cleaned = text
        if cleaned.unicodeScalars.first == "\u{FEFF}" { cleaned.unicodeScalars.removeFirst() }
        return cleaned.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let englishMonths = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// "04.11.2026" or "03.Jan.2000".
    static func parseDate(_ text: String) -> CalendarDay? {
        if let day = CalendarDay(czech: text) { return day }
        let parts = text.split(separator: ".")
        guard parts.count == 3, let d = Int(parts[0]), let y = Int(parts[2]) else { return nil }
        guard let monthIndex = englishMonths.firstIndex(of: parts[1].lowercased()) else { return nil }
        return CalendarDay(year: y, month: monthIndex + 1, day: d)
    }
}
