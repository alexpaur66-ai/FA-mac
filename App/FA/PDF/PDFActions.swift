// The PDF actions shared by the File menu and the detail column (screens-flows.md §1.4, §2b): Save PDF…,
// Show PDF in Finder and Print…, and the banner shown when Issue could not write the PDF file.

import AppKit
import InvoicingCore
import InvoicingData
import InvoicingPDF

/// Issue stored the PDF but could not write the file into the PDF folder (screens-flows.md §2c): the
/// document is issued either way, and the detail shows a banner with Choose Folder… and Save PDF….
struct PDFSaveFailure: Equatable {
    let documentID: String
    /// The folder the write was aimed at, for display.
    let folder: String
    let detail: String
}

@MainActor
enum PDFActions {
    /// Save PDF… on an issued document: its stored bytes through a save panel; the path is remembered.
    /// Nil when the panel was cancelled.
    static func save(_ stores: Stores, documentID: String) throws -> URL? {
        let (document, stored) = try issued(stores, documentID: documentID)
        guard let url = try PDFFiles.saveWithPanel(stored.data, suggestedName: DocumentPDF.fileName(for: document)) else { return nil }
        try stores.documents.recordSavedPDF(documentID: documentID, path: url.path)
        return url
    }

    /// Writes an issued document's stored PDF into `folder` (Choose Folder… on the failure banner).
    static func save(_ stores: Stores, documentID: String, into folder: URL) throws -> URL {
        let (document, stored) = try issued(stores, documentID: documentID)
        let url = try PDFSettings.save(stored.data, for: document, in: folder)
        try stores.documents.recordSavedPDF(documentID: documentID, path: url.path)
        return url
    }

    /// Print…: an issued document's stored PDF, or a draft as its watermarked preview (screens-flows.md §1.4).
    static func printPDF(_ stores: Stores, documentID: String, draft: Document?) throws {
        let data: Data
        if let draft {
            data = try DocumentPDFService.draftPreview(draft, profile: try stores.profile.load())
        } else {
            data = try DocumentPDFService.issuedPDF(stores, documentID: documentID).data
        }
        PDFFiles.printPDF(data, window: NSApp.keyWindow)
    }

    /// The saved file while it still exists; nil when the PDF was never saved or the file was moved, so
    /// Show PDF in Finder is disabled (screens-flows.md §2b).
    static func existingFile(_ stores: Stores, documentID: String) -> String? {
        guard let path = try? stores.documents.savedPDFPath(for: documentID), PDFFiles.fileExists(at: path) else { return nil }
        return path
    }

    private static func issued(_ stores: Stores, documentID: String) throws -> (Document, StoredDocumentPDF) {
        guard let document = try stores.documents.document(id: documentID) else { throw DataError.documentNotFound(documentID) }
        return (document, try DocumentPDFService.issuedPDF(stores, documentID: documentID))
    }
}
