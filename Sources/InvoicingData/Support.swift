import CryptoKit
import Foundation
import InvoicingCore

/// JSON for the snapshots stored in the database. Keys are sorted so the same value always gives the
/// same text and the same hash.
enum JSONCodec {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    /// Lower-case hex SHA-256 of the text, stored with issued documents (§ 35a odst. 3 ZDPH: electronic
    /// storage must keep data that guarantee the integrity of the document).
    static func sha256(_ text: String) -> String {
        sha256(Data(text.utf8))
    }

    /// The same hash over raw bytes: the stored PDF of an issued document.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum Timestamps {
    /// "2026-11-05T04:52:26Z": ISO 8601 in UTC, which sorts as text.
    static func string(_ date: Date) -> String { date.formatted(.iso8601) }
}

/// Amounts are stored as integer minor units (haléře, cents) next to the currency code (ADR 0001).
enum MinorUnits {
    static func of(_ value: Decimal, _ currency: Currency) throws -> Int64 {
        guard let units = Money(value, currency).minorUnitsIfRepresentable else {
            throw DataError.amountOutOfRange("\(value) \(currency.code)")
        }
        return units
    }

    static func ifPresent(_ value: Decimal?, _ currency: Currency) throws -> Int64? {
        guard let value else { return nil }
        return try of(value, currency)
    }

    static func money(_ units: Int64, _ currency: Currency) -> Money {
        Money(minorUnits: units, currency: currency)
    }
}

extension CalendarDay {
    /// A day read back from its stored ISO text.
    static func stored(_ text: String, table: String, id: String) throws -> CalendarDay {
        guard let day = CalendarDay(iso: text) else {
            throw DataError.corruptRecord(table: table, id: id, detail: "not a day: \(text)")
        }
        return day
    }

    /// The optional column: nil stays nil. The explicit type picks the non-optional overload above, which
    /// the compiler otherwise finds ambiguous with this one.
    static func stored(_ text: String?, table: String, id: String) throws -> CalendarDay? {
        guard let text else { return nil }
        let day: CalendarDay = try stored(text, table: table, id: id)
        return day
    }
}
