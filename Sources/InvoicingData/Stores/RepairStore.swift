import Foundation
import GRDB
import InvoicingCore

/// What Repair mode can change on an issued document in this version (screens-flows.md §2m): the client's
/// details as printed, the due date, the order reference and the note. None of them changes an amount, a
/// date the VAT depends on, or the number.
public struct DocumentHeaderRepair: Hashable, Sendable {
    public var customer: Party
    public var dueDate: CalendarDay
    public var orderReference: String?
    public var note: String?

    public init(customer: Party, dueDate: CalendarDay, orderReference: String?, note: String?) {
        self.customer = customer
        self.dueDate = dueDate
        self.orderReference = orderReference
        self.note = note
    }

    /// The values as the document holds them.
    public init(_ document: Document) {
        self.init(customer: document.customer, dueDate: document.dueDate, orderReference: document.orderReference, note: document.note)
    }

    /// A text that differs from the stored one only in surrounding blanks is not a change: the stored text
    /// stays exactly as it is, so an untouched field is never logged and Undo restores the exact snapshot.
    func apply(to document: inout Document) {
        document.customer = customer
        document.dueDate = dueDate
        if Self.cleaned(orderReference) != Self.cleaned(document.orderReference) {
            document.orderReference = Self.cleaned(orderReference)
        }
        if Self.cleaned(note) != Self.cleaned(document.note) {
            document.note = Self.cleaned(note)
        }
    }

    /// `current` with the fields in `fields` set back to the values this header holds; the client's details
    /// go back as a whole. Undo uses it so it takes back only its own change, not a later one.
    public func restoring(_ fields: Set<RepairField>, onto current: DocumentHeaderRepair) -> DocumentHeaderRepair {
        var header = current
        if fields.contains(where: { $0.rawValue.hasPrefix("customer") }) { header.customer = customer }
        if fields.contains(.dueDate) { header.dueDate = dueDate }
        if fields.contains(.orderReference) { header.orderReference = orderReference }
        if fields.contains(.note) { header.note = note }
        return header
    }

    /// Empty text is no text.
    private static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// A field Repair mode changed; its raw value is the `field` of the audit event.
public enum RepairField: String, Sendable, CaseIterable {
    case customerName, customerAddress, customerCompanyID, customerVATID, customerRegistry, customerEmail, customerPhone
    case dueDate, orderReference, note
}

/// One changed field, as the audit event records it: the old and the new value as text ("" for none).
public struct RepairChange: Hashable, Sendable {
    public let field: RepairField
    public let old: String
    public let new: String

    public init(field: RepairField, old: String, new: String) {
        self.field = field
        self.old = old
        self.new = new
    }
}

public enum RepairError: Error, Equatable, Sendable {
    /// Every repair change carries a reason.
    case reasonRequired
    /// The repair would change nothing.
    case nothingChanged
}

/// The result of a repair: the document as stored now, what it held before (for Undo) and what changed.
public struct DocumentRepairResult: Sendable {
    public let document: Document
    public let before: DocumentHeaderRepair
    public let changes: [RepairChange]
}

/// Repair mode's changes to issued records (screens-flows.md §2m). Each repair is one transaction: the lock
/// opens for it alone, every changed field writes an audit event with its old and new value and the reason,
/// and a new PDF replaces the stored one while the old bytes stay in `documentPDFHistory`. If any of it fails,
/// nothing is saved. There is no way to change a locked record without an audit event.
public struct RepairStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// The header of the issued document as stored now.
    public func header(documentID: String) throws -> DocumentHeaderRepair {
        try database.queue.read { db in
            let (_, document) = try Self.issued(db, id: documentID)
            return DocumentHeaderRepair(document)
        }
    }

    /// The issued document with `repair` applied, checked but not stored: the app renders its new PDF from it.
    public func preview(documentID: String, repair: DocumentHeaderRepair) throws -> Document {
        try database.queue.read { db in
            let (_, document) = try Self.issued(db, id: documentID)
            return try Self.repaired(document, with: repair)
        }
    }

    /// Stores the repair of an issued document with `reason`, and `pdf` (rendered from `preview`) as its new
    /// PDF when given. Throws `reasonRequired`, `nothingChanged`, or `validationFailed` for a problem the
    /// repair would add.
    @discardableResult
    public func repair(documentID: String, repair: DocumentHeaderRepair, reason: String, pdf: Data?,
                       now: Date = Date()) throws -> DocumentRepairResult {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { throw RepairError.reasonRequired }
        return try database.queue.write { db in
            let (record, document) = try Self.issued(db, id: documentID)
            let repaired = try Self.repaired(document, with: repair)
            let changes = Self.changes(from: document, to: repaired)
            guard !changes.isEmpty else { throw RepairError.nothingChanged }
            let stamp = Timestamps.string(now)
            let totals = try DocumentTotals.compute(for: repaired)
            let updated = try DocumentRecord(document: repaired, totals: totals, createdAt: record.createdAt, updatedAt: stamp,
                                             issuedAt: record.issuedAt, issueDateSetByHand: record.issueDateSetByHand,
                                             taxPointSetByHand: record.taxPointSetByHand)
            try Self.unlocked(db) {
                try updated.update(db)
                if let pdf {
                    try Self.replacePDF(db, documentID: documentID, data: pdf, reason: reason, at: stamp)
                }
            }
            for change in changes {
                try AuditLog.append(db, entity: "document", id: documentID, action: "repair",
                                    details: ["field": change.field.rawValue, "old": change.old, "new": change.new,
                                              "reason": reason, "sha256": updated.snapshotSHA256 ?? ""],
                                    at: stamp)
            }
            return DocumentRepairResult(document: repaired, before: DocumentHeaderRepair(document), changes: changes)
        }
    }

    /// How many stored PDFs of the document repairs replaced; their bytes stay in `documentPDFHistory`.
    public func replacedPDFCount(documentID: String) throws -> Int {
        try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documentPDFHistory WHERE documentID = ?", arguments: [documentID]) ?? 0
        }
    }

    // MARK: Inside the transaction

    private static func issued(_ db: Database, id: String) throws -> (DocumentRecord, Document) {
        guard let record = try DocumentRecord.fetchOne(db, key: id) else { throw DataError.documentNotFound(id) }
        let document = try record.decode()
        guard record.status == DocumentStatus.issued.rawValue, document.status == .issued else { throw DataError.documentNotIssued(id) }
        return (record, document)
    }

    /// `repair` applied to `document`. Refused when it adds a problem the validator reports as an error; one
    /// the document already had (a rule added after it was issued) does not block the repair.
    static func repaired(_ document: Document, with repair: DocumentHeaderRepair) throws -> Document {
        var repaired = document
        repair.apply(to: &repaired)
        let before = Set(DocumentValidator.validate(document, forIssue: true).filter(\.isError))
        let added = DocumentValidator.validate(repaired, forIssue: true).filter { $0.isError && !before.contains($0) }
        guard added.isEmpty else { throw DataError.validationFailed(added) }
        return repaired
    }

    /// Every field that differs, in a fixed order, so the audit trail names each one.
    static func changes(from old: Document, to new: Document) -> [RepairChange] {
        // As printed, with the country always: "Krátká 1, 602 00 Brno, CZ".
        func text(_ address: PostalAddress) -> String {
            address.lines(alwaysIncludeCountry: true).joined(separator: ", ")
        }
        func registry(_ entry: RegistryEntry?) -> String {
            entry.map { $0.court.rawValue + " " + $0.fileNumber } ?? ""
        }
        let pairs: [(RepairField, String, String)] = [
            (.customerName, old.customer.name, new.customer.name),
            (.customerAddress, text(old.customer.address), text(new.customer.address)),
            (.customerCompanyID, old.customer.identificationNumber?.digits ?? "", new.customer.identificationNumber?.digits ?? ""),
            (.customerVATID, old.customer.vatIdentifier?.value ?? "", new.customer.vatIdentifier?.value ?? ""),
            (.customerRegistry, registry(old.customer.registryEntry), registry(new.customer.registryEntry)),
            (.customerEmail, old.customer.email ?? "", new.customer.email ?? ""),
            (.customerPhone, old.customer.phone ?? "", new.customer.phone ?? ""),
            (.dueDate, old.dueDate.isoString, new.dueDate.isoString),
            (.orderReference, old.orderReference ?? "", new.orderReference ?? ""),
            (.note, old.note ?? "", new.note ?? ""),
        ]
        var changes = pairs.filter { $0.1 != $0.2 }.map { RepairChange(field: $0.0, old: $0.1, new: $0.2) }
        // An address that differs only where the text above cannot show it (a country code written in
        // another case, say) is still a change, and still logged.
        if old.customer != new.customer, changes.allSatisfy({ !$0.field.rawValue.hasPrefix("customer") }) {
            changes.insert(RepairChange(field: .customerAddress, old: text(old.customer.address), new: text(new.customer.address)), at: 0)
        }
        return changes
    }

    /// Runs `body` with the locks of issued records open; they close again before the transaction commits.
    static func unlocked(_ db: Database, _ body: () throws -> Void) throws {
        let token = UUID().uuidString
        try db.execute(sql: "INSERT INTO repairUnlock (token) VALUES (?)", arguments: [token])
        try body()
        try db.execute(sql: "DELETE FROM repairUnlock WHERE token = ?", arguments: [token])
    }

    /// Moves the stored PDF's bytes to the history and stores `data` in their place. A document without a
    /// stored PDF just gets one.
    private static func replacePDF(_ db: Database, documentID: String, data: Data, reason: String, at stamp: String) throws {
        let sha = JSONCodec.sha256(data)
        if let old = try DocumentPDFRecord.fetchOne(db, key: documentID) {
            try db.execute(sql: """
                INSERT INTO documentPDFHistory (documentID, data, sha256, renderedAt, replacedAt) VALUES (?, ?, ?, ?, ?)
                """, arguments: [documentID, old.data, old.sha256, old.renderedAt, stamp])
            try db.execute(sql: "UPDATE documentPDF SET data = ?, sha256 = ?, renderedAt = ? WHERE documentID = ?",
                           arguments: [data, sha, stamp, documentID])
            try AuditLog.append(db, entity: "document", id: documentID, action: "pdfReplaced",
                                details: ["oldSHA256": old.sha256, "sha256": sha, "bytes": String(data.count), "reason": reason], at: stamp)
        } else {
            let pdf = DocumentPDFRecord(documentID: documentID, data: data, sha256: sha, renderedAt: stamp, savedPath: nil, savedAt: nil)
            try pdf.insert(db)
            try AuditLog.append(db, entity: "document", id: documentID, action: "pdf",
                                details: ["sha256": sha, "bytes": String(data.count)], at: stamp)
        }
    }
}
