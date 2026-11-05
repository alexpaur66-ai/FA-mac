// The PDF of a document (ADR 0010): an issued document's bytes are rendered once and stored with it; a
// draft is rendered live for the preview, with the company's account standing in for the payment
// instructions that Issue fills in.

import Foundation
import InvoicingCore
import InvoicingData
import InvoicingPDF

enum DocumentPDFService {
    /// The stored PDF of an issued document. A document without one (issued before the PDF step, or a
    /// render that failed at issue) is rendered from its frozen snapshot and stored now.
    static func issuedPDF(_ stores: Stores, documentID: String) throws -> StoredDocumentPDF {
        if let stored = try stores.documents.pdf(for: documentID) {
            return stored
        }
        guard let document = try stores.documents.document(id: documentID) else { throw DataError.documentNotFound(documentID) }
        guard document.status == .issued else { throw DataError.documentNotIssued(documentID) }
        return try stores.documents.storePDF(documentID: documentID, data: try DocumentPDF.render(document))
    }

    /// Renders and stores the PDF of a document that was just issued, then writes it to the PDF folder when
    /// one is chosen and automatic saving is on. Returns the file written, or nil when nothing was to be
    /// written. A failed write is thrown after the bytes are stored: the document is issued either way
    /// (screens-flows.md §2c, "the database is the source of truth").
    @discardableResult
    static func storeAndSave(_ stores: Stores, document: Document) throws -> URL? {
        let stored = try stores.documents.storePDF(documentID: document.id, data: try DocumentPDF.render(document))
        guard PDFSettings.autoSaveOnIssue, let folder = PDFSettings.folderURL() else { return nil }
        let url = try PDFSettings.save(stored.data, for: document, in: folder)
        try stores.documents.recordSavedPDF(documentID: document.id, path: url.path)
        return url
    }

    /// A draft as it would print once issued, except for the draft markers (screens-flows.md §2c).
    static func draftPreview(_ document: Document, profile: CompanyProfile?) throws -> Data {
        var draft = document
        draft.status = .draft
        if draft.payment == nil, let account = profile?.bankConnection(for: draft.currency) {
            let qrCode: PaymentQRKind
            switch draft.currency {
            case .czk: qrCode = .qrPlatba
            case .eur: qrCode = .sepa
            default: qrCode = .none
            }
            draft.payment = PaymentInstructions(bankConnection: account, qrCode: qrCode)
        }
        return try DocumentPDF.render(draft)
    }
}
