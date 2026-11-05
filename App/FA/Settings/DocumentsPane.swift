// Settings ▸ Documents & PDF (screens-flows.md §2i, ADR 0010): the PDF folder, automatic saving at issue,
// the year subfolder and the fixed file-name pattern. The folder is a security-scoped bookmark the user
// grants through the open panel; the app never writes anywhere else.

import AppKit
import SwiftUI

struct DocumentsPane: View {
    @State private var folderURL: URL?
    @State private var message: String?
    @AppStorage(PDFSettings.autoSaveKey) private var autoSave = true
    @AppStorage(PDFSettings.yearSubfolderKey) private var yearSubfolder = true
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        if let folderURL {
                            Text(verbatim: PDFSettings.displayPath(folderURL)).textRole(.caption).textSelection(.enabled)
                        } else {
                            Text(L.pdfFolderNone).textRole(.caption)
                        }
                        HStack(spacing: Spacing.s) {
                            if let folderURL {
                                Button { NSWorkspace.shared.activateFileViewerSelecting([folderURL]) } label: { Text(L.showInFinder) }
                                Button { forgetFolder() } label: { Text(L.clearFolder) }
                            }
                            Button { chooseFolder() } label: { Text(L.chooseFolder) }
                        }
                    }
                } label: {
                    Text(L.pdfFolder)
                }
                Toggle(isOn: $autoSave) { Text(L.pdfAutoSave) }
                    .disabled(folderURL == nil)
                Toggle(isOn: $yearSubfolder) { Text(L.pdfYearSubfolder) }
                LabeledContent {
                    Text(L.pdfFileNamePattern).textRole(.caption)
                } label: {
                    Text(L.pdfFileName)
                }
                if folderURL == nil {
                    Text(L.pdfNoFolder).textRole(.caption)
                }
            } header: {
                Text(L.pdfSection)
            }
            Section {
                Text(L.documentsPaneNote).textRole(.caption)
            }
            if let message {
                Section {
                    Text(verbatim: message).textRole(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { folderURL = PDFSettings.folderURL() }
    }

    private func chooseFolder() {
        do {
            if let url = try PDFFiles.chooseFolder() {
                folderURL = url
                message = nil
            }
        } catch {
            message = ErrorText.message(error, locale: locale)
        }
    }

    private func forgetFolder() {
        do {
            try PDFSettings.setFolder(nil)
            folderURL = nil
            message = nil
        } catch {
            message = ErrorText.message(error, locale: locale)
        }
    }
}
