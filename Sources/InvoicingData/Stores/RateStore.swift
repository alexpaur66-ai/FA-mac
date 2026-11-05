import Foundation
import GRDB
import InvoicingCore

/// ČNB exchange rates (§ 4 odst. 8 ZDPH). The app has no network access: rates come from the ČNB text
/// files the user downloads and imports, or are typed in. One row per currency and day.
public struct RateStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Inserts or replaces the rate of its currency and day.
    public func save(_ rate: ExchangeRate, now: Date = Date()) throws {
        try database.queue.write { db in try Self.save([rate], db, now: now) }
    }

    /// Imports a ČNB daily file ("denni_kurz.txt"); returns the number of rates stored.
    @discardableResult
    public func importDaily(_ text: String, now: Date = Date()) throws -> Int {
        let file = try CNBRateFile.parseDaily(text)
        try database.queue.write { db in try Self.save(file.rates, db, now: now) }
        return file.rates.count
    }

    /// Imports a ČNB yearly file ("rok.txt"); returns the number of rates stored.
    @discardableResult
    public func importYearly(_ text: String, now: Date = Date()) throws -> Int {
        let rates = try CNBRateFile.parseYearly(text)
        try database.queue.write { db in try Self.save(rates, db, now: now) }
        return rates.count
    }

    private static func save(_ rates: [ExchangeRate], _ db: Database, now: Date) throws {
        let stamp = Timestamps.string(now)
        for rate in rates {
            try ExchangeRateRecord(rate, importedAt: stamp).save(db)
        }
    }

    /// All stored rates of a currency, oldest first.
    public func rates(for currency: Currency) throws -> [ExchangeRate] {
        try database.queue.read { db in
            try ExchangeRateRecord.filter(Column("currency") == currency.code).order(Column("validFor")).fetchAll(db).map { try $0.rate() }
        }
    }

    public func table(for currency: Currency) throws -> ExchangeRateTable {
        ExchangeRateTable(rates: try rates(for: currency))
    }

    /// The rate for `day`: the one published for that day, or by default the last one published on or
    /// before it (the ČNB publishes on working days only).
    public func rate(for currency: Currency, on day: CalendarDay, lookup: ExchangeRateTable.Lookup = .lastPublishedOnOrBefore) throws -> ExchangeRate? {
        try database.queue.read { db in
            var request = ExchangeRateRecord.filter(Column("currency") == currency.code)
            switch lookup {
            case .exactDay:
                request = request.filter(Column("validFor") == day.isoString)
            case .lastPublishedOnOrBefore:
                request = request.filter(Column("validFor") <= day.isoString).order(Column("validFor").desc)
            }
            return try request.fetchOne(db)?.rate()
        }
    }

    public func latestDay(for currency: Currency) throws -> CalendarDay? {
        try database.queue.read { db in
            try ExchangeRateRecord.filter(Column("currency") == currency.code).order(Column("validFor").desc).fetchOne(db)
                .map { try CalendarDay.stored($0.validFor, table: ExchangeRateRecord.databaseTableName, id: "\($0.currency) \($0.validFor)") }
        }
    }
}
