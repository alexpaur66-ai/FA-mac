import Foundation
import GRDB
import InvoicingCore

/// Numbering series. The counter advances only inside `DocumentStore.issue`, in the same transaction as
/// the document, so a number is never skipped or used twice (§ 29 odst. 1 písm. e) ZDPH).
public struct NumberSeriesStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Inserts or replaces a series. Replacing a series that has issued numbers with a lower counter or an
    /// earlier year would reuse numbers, so the stored year and counter never move backwards, whatever the
    /// template: name, kinds, template and yearly reset stay editable, the counter carries on.
    public func save(_ stored: StoredNumberSeries, now: Date = Date()) throws {
        try database.queue.write { db in
            let existing = try NumberSeriesRecord.fetchOne(db, key: stored.id)
            var record = NumberSeriesRecord(stored)
            if let existing {
                if existing.resetsYearly && record.resetsYearly {
                    // The counter belongs to its year: keep the stored pair when it is ahead.
                    if (existing.year, existing.lastCounter) > (record.year, record.lastCounter) {
                        record.year = existing.year
                        record.lastCounter = existing.lastCounter
                        record.lastIssuedYear = existing.lastIssuedYear
                    }
                } else {
                    // A counter that does not restart yearly only grows.
                    if existing.lastCounter > record.lastCounter {
                        record.lastCounter = existing.lastCounter
                        record.lastIssuedYear = existing.lastIssuedYear
                    }
                    record.year = max(record.year, existing.year)
                }
            }
            try record.save(db)
            try AuditLog.append(db, entity: "numberSeries", id: stored.id, action: existing == nil ? "create" : "update",
                                details: ["template": record.template, "lastCounter": String(record.lastCounter)], at: Timestamps.string(now))
        }
    }

    public func series(id: String) throws -> StoredNumberSeries? {
        try database.queue.read { db in try NumberSeriesRecord.fetchOne(db, key: id)?.stored() }
    }

    public func all() throws -> [StoredNumberSeries] {
        try database.queue.read { db in
            try NumberSeriesRecord.order(Column("name")).fetchAll(db).map { try $0.stored() }
        }
    }

    /// Series that number documents of `kind`.
    public func series(for kind: DocumentKind) throws -> [StoredNumberSeries] {
        try all().filter { $0.numbers(kind) }
    }

    /// The number the next document dated `day` would get, without issuing it.
    public func peekNextNumber(seriesID: String, on day: CalendarDay) throws -> String {
        guard let stored = try series(id: seriesID) else { throw DataError.seriesNotFound(seriesID) }
        return try stored.series.peek(on: day)
    }

    // MARK: The three fixed series (set-09)

    /// The series a document of `kind` is numbered from: its section's series, when that numbers the kind.
    /// Other stored series number nothing new (there is no series picker).
    public func issuingSeries(for kind: DocumentKind) throws -> StoredNumberSeries? {
        guard let stored = try sections()[NumberingSection(kind)], stored.numbers(kind) else { return nil }
        return stored
    }

    /// Each section's series: the one with the section's default id, else the first series (by name) that
    /// numbers the section's first kind and no other section took.
    public func sections() throws -> [NumberingSection: StoredNumberSeries] {
        try database.queue.read { db in try Self.sections(db) }
    }

    static func sections(_ db: Database) throws -> [NumberingSection: StoredNumberSeries] {
        let all = try NumberSeriesRecord.order(Column("name")).fetchAll(db).map { try $0.stored() }
        var result: [NumberingSection: StoredNumberSeries] = [:]
        var taken: Set<String> = []
        for section in NumberingSection.allCases {
            if let byID = all.first(where: { $0.id == section.rawValue }) {
                result[section] = byID
                taken.insert(byID.id)
            }
        }
        for section in NumberingSection.allCases where result[section] == nil {
            if let byKind = all.first(where: { !taken.contains($0.id) && $0.numbers(section.primaryKind) }) {
                result[section] = byKind
                taken.insert(byKind.id)
            }
        }
        return result
    }

    /// Creates the default series of every section that has none (a new database gets all three; an
    /// existing one keeps its series and gets no second set), in `year`. Returns the ids created.
    @discardableResult
    public func ensureDefaultSeries(year: Int, now: Date = Date()) throws -> [String] {
        try database.queue.write { db in
            let mapped = try Self.sections(db)
            var created: [String] = []
            for section in NumberingSection.allCases where mapped[section] == nil {
                guard try NumberSeriesRecord.fetchOne(db, key: section.rawValue) == nil else { continue }
                let series = try DocumentNumberSeries(id: section.rawValue, pattern: DocumentNumberPattern(template: section.defaultTemplate),
                                                      year: year, variableSymbolPrefix: section.variableSymbolPrefix)
                let record = NumberSeriesRecord(StoredNumberSeries(name: section.defaultName, kinds: section.kinds, series: series))
                try record.insert(db)
                try AuditLog.append(db, entity: "numberSeries", id: section.rawValue, action: "create",
                                    details: ["template": record.template, "lastCounter": "0"], at: Timestamps.string(now))
                created.append(section.rawValue)
            }
            return created
        }
    }

    /// True once Saša saved Settings ▸ Numbering, or a section's series has already issued a number (an
    /// install updated after real issuing). Until then Issue shows "Confirm your number series".
    public func isNumberingConfirmed() throws -> Bool {
        try database.queue.read { db in
            if try String.fetchOne(db, sql: "SELECT value FROM appState WHERE key = ?", arguments: [Self.confirmedKey]) != nil {
                return true
            }
            return try Self.sections(db).values.contains { $0.series.lastIssuedYear != nil }
        }
    }

    /// Records that Saša confirmed the number series (Save in Settings ▸ Numbering).
    public func confirmNumbering(now: Date = Date()) throws {
        try database.queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO appState (key, value) VALUES (?, ?)",
                           arguments: [Self.confirmedKey, Timestamps.string(now)])
            try AuditLog.append(db, entity: "numberSeries", id: "all", action: "confirm", at: Timestamps.string(now))
        }
    }

    static let confirmedKey = "numberingConfirmed"

    public func delete(id: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard try NumberSeriesRecord.deleteOne(db, key: id) else { throw DataError.seriesNotFound(id) }
            try AuditLog.append(db, entity: "numberSeries", id: id, action: "delete", at: Timestamps.string(now))
        }
    }
}

/// The three fixed series of Settings ▸ Numbering (set-09), named by their default ids.
public enum NumberingSection: String, CaseIterable, Hashable, Sendable {
    /// FV {YYYY}-{NNNN}, VS prefix 1: invoices and final invoices.
    case invoices = "invoice"
    /// ZF {YYYY}-{NNNN}, VS prefix 2: advance invoices.
    case advances = "advance"
    /// DD {YYYY}-{NNNN}, no prefix: tax documents for received payments, which carry no variable symbol.
    case paymentReceipts = "paymentReceipt"

    public init(_ kind: DocumentKind) {
        switch kind {
        case .invoice, .finalInvoice: self = .invoices
        case .advanceRequest: self = .advances
        case .paymentTaxDocument: self = .paymentReceipts
        }
    }

    public var kinds: Set<DocumentKind> {
        switch self {
        case .invoices: [.invoice, .finalInvoice]
        case .advances: [.advanceRequest]
        case .paymentReceipts: [.paymentTaxDocument]
        }
    }

    /// The kind an older series must number to be mapped to this section.
    var primaryKind: DocumentKind {
        switch self {
        case .invoices: .invoice
        case .advances: .advanceRequest
        case .paymentReceipts: .paymentTaxDocument
        }
    }

    public var defaultTemplate: String {
        switch self {
        case .invoices: "FV {YYYY}-{NNNN}"
        case .advances: "ZF {YYYY}-{NNNN}"
        case .paymentReceipts: "DD {YYYY}-{NNNN}"
        }
    }

    /// The fixed variable-symbol prefix (ADR 0003 addendum); nil for DD.
    public var variableSymbolPrefix: String? {
        switch self {
        case .invoices: "1"
        case .advances: "2"
        case .paymentReceipts: nil
        }
    }

    /// The stored name of a series the database creates (the pane shows its own section headers).
    public var defaultName: String {
        switch self {
        case .invoices: "Invoices"
        case .advances: "Advance invoices"
        case .paymentReceipts: "Tax documents for received payments"
        }
    }
}
