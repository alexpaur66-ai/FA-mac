import Foundation
import GRDB
import InvoicingCore

/// A month exported for the accountant (screens-flows.md §2h): when, into which folder, and which documents
/// it held. Exporting the month again replaces it.
public struct MonthExport: Hashable, Sendable {
    /// The first day of the month.
    public let month: CalendarDay
    /// ISO 8601 UTC.
    public let exportedAt: String
    /// The folder the files were written into.
    public let folder: String
    /// Document id → the SHA-256 of its snapshot as exported.
    public let documents: [String: String]
}

struct MonthExportRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "monthExport"
    var month: String
    var exportedAt: String
    var folder: String
    var documents: String

    func export() throws -> MonthExport {
        guard let day = CalendarDay(iso: month + "-01") else {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: month, detail: "not a month")
        }
        let hashes: [String: String]
        do { hashes = try JSONCodec.decode([String: String].self, from: documents) } catch {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: month, detail: "\(error)")
        }
        return MonthExport(month: day, exportedAt: exportedAt, folder: folder, documents: hashes)
    }
}

/// An exported month in which documents were issued (or changed) after its export: the Overview queue row
/// "October 2026 · 1 document changed after export" (screens-flows.md §2a).
public struct MonthExportChange: Hashable, Sendable {
    public let export: MonthExport
    public let changedCount: Int
}

/// One issued document of the month, with what its CSV row needs.
public struct ExportedDocument: Sendable {
    public let document: Document
    public let state: DocumentState
    public let totals: DocumentTotals
    /// The stored hash of the issued snapshot.
    public let sha256: String
    /// Its payments, in date order.
    public let payments: [DocumentPayment]
    /// The advance of a payment tax document; the advances and payment tax documents a final invoice
    /// deducts or settles (screens-flows.md §2h, RelatedDocs).
    public let relatedNumbers: [String]
}

/// One payment of the month, with the document it was recorded on.
public struct ExportedPayment: Sendable {
    public let payment: DocumentPayment
    public let documentNumber: String
    public let documentKind: DocumentKind
    public let customerName: String
    /// The issued payment tax document of the payment, if any.
    public let receiptNumber: String?
}

/// What Export for Accountant writes for one month (screens-flows.md §2h): the issued documents that belong to
/// the month by `Document.exportDay` and the payments by payment date.
public struct AccountantExportData: Sendable {
    /// The first day of the month.
    public let month: CalendarDay
    public let documents: [ExportedDocument]
    public let payments: [ExportedPayment]

    public var advanceCount: Int { documents.filter { $0.document.kind == .advanceRequest }.count }

    /// Czech VAT of the month's tax documents, net of the advance VAT a final invoice deducts (the §2a
    /// aggregation rules, as the Overview's VAT tile). § 64 goods and advances carry none.
    public var vatCZK: Decimal {
        documents.filter { $0.document.kind.isTaxDocument }.reduce(Decimal(0)) { $0 + ($1.totals.taxableVATCZK ?? 0) }
    }
}

/// The export records and the data of a month's export (screens-flows.md §2h).
public struct ExportStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    static func key(_ month: CalendarDay) -> String { String(month.startOfMonth.isoString.prefix(7)) }

    /// Every export record, the latest month first.
    public func records() throws -> [MonthExport] {
        try database.queue.read { db in
            try MonthExportRecord.order(Column("month").desc).fetchAll(db).map { try $0.export() }
        }
    }

    /// The month's export record; nil when the month was never exported.
    public func record(month: CalendarDay) throws -> MonthExport? {
        try database.queue.read { db in try MonthExportRecord.fetchOne(db, key: Self.key(month))?.export() }
    }

    /// The folder of the latest export, for the next save panel; nil before the first export.
    public func lastFolder() throws -> String? {
        try database.queue.read { db in
            try String.fetchOne(db, sql: "SELECT folder FROM monthExport ORDER BY exportedAt DESC LIMIT 1")
        }
    }

    /// The issued documents of the month and the payments dated in it, as of `today` (for the status column).
    public func data(month: CalendarDay, today: CalendarDay) throws -> AccountantExportData {
        let first = month.startOfMonth
        return try database.queue.read { db in
            let records = try DocumentRecord.filter(Column("status") == DocumentStatus.issued.rawValue).fetchAll(db)
            var inMonth: [(record: DocumentRecord, document: Document)] = []
            var numbers: [String: String] = [:]
            for record in records {
                if let number = record.number { numbers[record.id] = number }
                let document = try record.decode()
                if document.exportDay.startOfMonth == first {
                    inMonth.append((record, document))
                }
            }
            inMonth.sort { lhs, rhs in
                let left = lhs.document.exportDay, right = rhs.document.exportDay
                if left != right { return left < right }
                return (lhs.record.number ?? "") < (rhs.record.number ?? "")
            }
            let states = try DocumentStore.states(db, records: inMonth.map(\.record), today: today)
            var documents: [ExportedDocument] = []
            for (index, entry) in inMonth.enumerated() {
                let payments = try DocumentPaymentRecord.filter(Column("documentID") == entry.record.id)
                    .order(Column("paidOn"), Column("createdAt")).fetchAll(db)
                    .map { try $0.payment(receiptIssued: try DocumentStore.receiptIsIssued(db, $0)) }
                documents.append(ExportedDocument(
                    document: entry.document, state: states[index], totals: try DocumentTotals.compute(for: entry.document),
                    sha256: entry.record.snapshotSHA256 ?? JSONCodec.sha256(entry.record.snapshot),
                    payments: payments, relatedNumbers: try Self.relatedNumbers(db, document: entry.document, numbers: numbers)))
            }

            let from = first.isoString, to = first.endOfMonth.isoString
            var payments: [ExportedPayment] = []
            for record in try DocumentPaymentRecord.filter(Column("paidOn") >= from && Column("paidOn") <= to)
                .order(Column("paidOn"), Column("createdAt")).fetchAll(db) {
                guard let owner = try DocumentRecord.fetchOne(db, key: record.documentID), owner.status == DocumentStatus.issued.rawValue,
                      let kind = DocumentKind(rawValue: owner.kind) else { continue }
                let payment = try record.payment(receiptIssued: try DocumentStore.receiptIsIssued(db, record))
                payments.append(ExportedPayment(
                    payment: payment, documentNumber: owner.number ?? "", documentKind: kind, customerName: owner.customerName,
                    receiptNumber: payment.receiptIssued ? record.receiptDocumentID.flatMap { numbers[$0] } : nil))
            }
            return AccountantExportData(month: first, documents: documents, payments: payments)
        }
    }

    /// RelatedDocs: a document's own related number (the advance of a payment tax document), then for a final
    /// invoice each deducted payment tax document with its advance, and each advance settled as paid in
    /// advance; each number once.
    static func relatedNumbers(_ db: Database, document: Document, numbers: [String: String]) throws -> [String] {
        var result: [String] = []
        func add(_ number: String?) {
            guard let number, !number.isEmpty, !result.contains(number) else { return }
            result.append(number)
        }
        add(document.relatedDocumentNumber)
        guard document.kind == .finalInvoice else { return result }
        for link in try AdvanceDeductionRecord.filter(Column("finalInvoiceID") == document.id).order(Column("receiptNumber")).fetchAll(db) {
            add(link.advanceRequestID.flatMap { numbers[$0] })
            add(link.receiptNumber)
        }
        for link in try PaidAdvanceRecord.filter(Column("finalInvoiceID") == document.id).order(Column("advanceNumber")).fetchAll(db) {
            add(link.advanceNumber)
        }
        return result
    }

    /// Writes the month's two CSV files into `folder` (created when missing; files of the same name are
    /// replaced) and then records the export, so a write that fails records nothing. Returns the files written.
    @discardableResult
    public func write(_ data: AccountantExportData, labels: AccountantExportLabels = .english, to folder: URL,
                      now: Date = Date()) throws -> [URL] {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let documentsURL = folder.appendingPathComponent(AccountantCSV.documentsFileName(data.month), isDirectory: false)
        let paymentsURL = folder.appendingPathComponent(AccountantCSV.paymentsFileName(data.month), isDirectory: false)
        try AccountantCSV.encoded(AccountantCSV.documents(data, labels: labels)).write(to: documentsURL, options: .atomic)
        try AccountantCSV.encoded(AccountantCSV.payments(data, labels: labels)).write(to: paymentsURL, options: .atomic)
        try recordExport(data, folder: folder.path, now: now)
        return [documentsURL, paymentsURL]
    }

    /// Keeps the month's export record (one per month: a later export replaces it), with an audit event.
    public func recordExport(_ data: AccountantExportData, folder: String, now: Date = Date()) throws {
        let stamp = Timestamps.string(now)
        var hashes: [String: String] = [:]
        for exported in data.documents { hashes[exported.document.id] = exported.sha256 }
        let record = MonthExportRecord(month: Self.key(data.month), exportedAt: stamp, folder: folder,
                                       documents: try JSONCodec.encode(hashes))
        try database.queue.write { db in
            try record.save(db)
            try AuditLog.append(db, entity: "monthExport", id: record.month, action: "exported",
                                details: ["folder": folder, "documents": String(hashes.count), "payments": String(data.payments.count)],
                                at: stamp)
        }
    }

    /// The exported months with documents issued, or changed, after their export: a document of the month
    /// that the export did not hold, or held with another snapshot. Latest month first.
    public func changedAfterExport() throws -> [MonthExportChange] {
        try database.queue.read { db in
            let exports = try MonthExportRecord.fetchAll(db).map { try $0.export() }
            guard let earliest = exports.map(\.exportedAt).min() else { return [] }
            var owner: [String: (month: String, sha: String)] = [:]
            for export in exports {
                for (id, sha) in export.documents { owner[id] = (Self.key(export.month), sha) }
            }
            var counts: [String: Int] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, snapshotSHA256, issuedAt FROM document WHERE status = ?
                """, arguments: [DocumentStatus.issued.rawValue])
            for row in rows {
                let id: String = row["id"]
                let sha: String? = row["snapshotSHA256"]
                if let known = owner[id] {
                    if let sha, sha != known.sha { counts[known.month, default: 0] += 1 }
                    continue
                }
                // A document issued before every export was either in the export of its month or belongs to a
                // month never exported, so only later ones are read.
                let issuedAt: String? = row["issuedAt"]
                guard let issuedAt, issuedAt >= earliest,
                      let record = try DocumentRecord.fetchOne(db, key: id) else { continue }
                let key = Self.key(try record.decode().exportDay)
                guard exports.contains(where: { Self.key($0.month) == key }) else { continue }
                counts[key, default: 0] += 1
            }
            return exports.compactMap { export -> MonthExportChange? in
                guard let count = counts[Self.key(export.month)], count > 0 else { return nil }
                return MonthExportChange(export: export, changedCount: count)
            }
            .sorted { $0.export.month > $1.export.month }
        }
    }
}
