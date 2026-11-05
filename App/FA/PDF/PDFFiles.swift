// The panels and system services around a document's PDF: Save PDF… (a save panel), the PDF folder
// chooser, Show PDF in Finder and Print… through the system print panel (screens-flows.md §1.4).

import AppKit
import InvoicingCore
import PDFKit
import UniformTypeIdentifiers

@MainActor
enum PDFFiles {
    /// Lets the user pick the PDF folder and keeps it; nil when cancelled.
    static func chooseFolder() throws -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: L.choose)
        panel.message = String(localized: L.pdfFolderPrompt)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try PDFSettings.setFolder(url)
        return url
    }

    /// Save PDF…: a save panel with the document's file name; returns the file written, nil when cancelled.
    static func saveWithPanel(_ data: Data, suggestedName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if let folder = PDFSettings.folderURL() {
            panel.directoryURL = folder
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }

    static func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Show PDF in Finder.
    static func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Print…: the document's PDF through the system print panel, one page per sheet, no scaling.
    /// `PDFDocument.printOperation(for:scalingMode:autoRotate:)` builds the operation; `PDFView` has no such method.
    static func printPDF(_ data: Data, window: NSWindow?) {
        guard let document = PDFDocument(data: data) else { return }
        guard let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleNone, autoRotate: false) else { return }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}
