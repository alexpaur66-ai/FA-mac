import Foundation
import GRDB
import InvoicingCore

/// The PDF of an issued document (ADR 0010). It is rendered once, when the document is issued, and
/// stored next to the frozen snapshot: the file the user keeps in a folder can move or vanish, the
/// stored bytes cannot (§ 35a odst. 3 ZDPH: electronic storage must guarantee the document's integrity).
public struct StoredDocumentPDF: Hashable, Sendable {
    public let documentID: String
    public let data: Data
    /// Lower-case hex SHA-256 of `data`.
    public let sha256: String
    /// ISO 8601 timestamp of the rendering.
    public let renderedAt: String
    /// Where the app last wrote the file, and when; nil until the first save.
    public let savedPath: String?
    public let savedAt: String?
}

struct DocumentPDFRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "documentPDF"
    var documentID: String
    var data: Data
    var sha256: String
    var renderedAt: String
    var savedPath: String?
    var savedAt: String?

    func stored() -> StoredDocumentPDF {
        StoredDocumentPDF(documentID: documentID, data: data, sha256: sha256, renderedAt: renderedAt, savedPath: savedPath, savedAt: savedAt)
    }
}

extension DocumentStore {
    /// Stores the PDF of an issued document. The first render is the one that stays: a later call returns
    /// the stored PDF unchanged, so a renderer change never rewrites evidence. Drafts have no stored PDF
    /// (`documentNotIssued`).
    @discardableResult
    public func storePDF(documentID: String, data: Data, now: Date = Date()) throws -> StoredDocumentPDF {
        try database.queue.write { db in
            guard let record = try DocumentRecord.fetchOne(db, key: documentID) else { throw DataError.documentNotFound(documentID) }
            guard record.status == DocumentStatus.issued.rawValue else { throw DataError.documentNotIssued(documentID) }
            if let existing = try DocumentPDFRecord.fetchOne(db, key: documentID) {
                return existing.stored()
            }
            let stamp = Timestamps.string(now)
            let pdf = DocumentPDFRecord(documentID: documentID, data: data, sha256: JSONCodec.sha256(data), renderedAt: stamp,
                                        savedPath: nil, savedAt: nil)
            try pdf.insert(db)
            try AuditLog.append(db, entity: "document", id: documentID, action: "pdf",
                                details: ["sha256": pdf.sha256, "bytes": String(data.count)], at: stamp)
            return pdf.stored()
        }
    }

    /// The stored PDF of a document, nil when none was stored yet.
    public func pdf(for documentID: String) throws -> StoredDocumentPDF? {
        try database.queue.read { db in try DocumentPDFRecord.fetchOne(db, key: documentID)?.stored() }
    }

    /// Remembers where the PDF file was last written (Show PDF in Finder, the inspector's "PDF file" row).
    public func recordSavedPDF(documentID: String, path: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard var pdf = try DocumentPDFRecord.fetchOne(db, key: documentID) else { throw DataError.pdfNotStored(documentID) }
            let stamp = Timestamps.string(now)
            pdf.savedPath = path
            pdf.savedAt = stamp
            try pdf.update(db)
            try AuditLog.append(db, entity: "document", id: documentID, action: "pdfSaved", details: ["path": path], at: stamp)
        }
    }
}
