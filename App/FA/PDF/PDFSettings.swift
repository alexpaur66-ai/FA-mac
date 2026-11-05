// Where PDFs go (screens-flows.md §2c step 6, §2i): the folder Saša chose, kept as a security-scoped
// bookmark, and the two switches of the Documents & PDF pane. Nonisolated, so views and the issue flow
// can read the defaults from anywhere.

import Foundation
import InvoicingCore
import InvoicingPDF

enum PDFSettings {
    static let folderBookmarkKey = "pdfFolderBookmark"
    static let autoSaveKey = "pdfAutoSaveOnIssue"
    static let yearSubfolderKey = "pdfYearSubfolder"

    /// "Save PDF automatically when issuing" (on by default, screens-flows.md §2i).
    static var autoSaveOnIssue: Bool {
        UserDefaults.standard.object(forKey: autoSaveKey) as? Bool ?? true
    }

    /// A subfolder per year of issue ("…/Faktury/2026/FV 2026-0042 Acme.pdf"), on by default.
    static var yearSubfolder: Bool {
        UserDefaults.standard.object(forKey: yearSubfolderKey) as? Bool ?? true
    }

    /// The chosen folder, resolved from its bookmark; nil when none was chosen, the bookmark no longer
    /// resolves, or the folder sits in the Trash. A stale bookmark is refreshed in place.
    static func folderURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: folderBookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: folderBookmarkKey)
        }
        // A deleted folder's bookmark resolves into the Trash; the PDFs must not be written there.
        return isInTrash(url) ? nil : url
    }

    /// True when `url` lies in a Trash folder (the user deleted the PDF folder after choosing it): the home
    /// Trash (`.Trash`) or the Trash of another volume (`/Volumes/X/.Trashes/501/…`).
    static func isInTrash(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if url.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" || $0.hasPrefix(".Trash-") }) {
            return true
        }
        var relationship = FileManager.URLRelationship.other
        if (try? FileManager.default.getRelationship(&relationship, of: .trashDirectory, in: .userDomainMask, toItemAt: url)) != nil,
           relationship == .contains {
            return true
        }
        return FileManager.default.urls(for: .trashDirectory, in: .allDomainsMask).contains { trash in
            path.hasPrefix(trash.standardizedFileURL.path + "/")
        }
    }

    /// Keeps `url` as the PDF folder (nil clears it). The bookmark needs the app-scope bookmark entitlement
    /// (FA.entitlements) and a URL the user picked in a panel.
    static func setFolder(_ url: URL?) throws {
        guard let url else {
            UserDefaults.standard.removeObject(forKey: folderBookmarkKey)
            return
        }
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: folderBookmarkKey)
    }

    /// The file an issued document's PDF takes in `folder`: the year subfolder when switched on, then
    /// "{number} {client}.pdf" (`DocumentPDF.fileName`).
    static func plannedURL(for document: Document, in folder: URL) -> URL {
        var target = folder
        if yearSubfolder {
            target.appendPathComponent(String(document.issueDate.year), isDirectory: true)
        }
        return target.appendingPathComponent(DocumentPDF.fileName(for: document), isDirectory: false)
    }

    /// Writes `data` to its planned file in `folder`, creating the year subfolder, and returns the file URL.
    /// The folder is reached through its security scope for the duration of the write.
    static func save(_ data: Data, for document: Document, in folder: URL) throws -> URL {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let url = plannedURL(for: document, in: folder)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// "~/Documents/Faktury/2026/FV-2026-001 Acme.pdf" for display.
    static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
