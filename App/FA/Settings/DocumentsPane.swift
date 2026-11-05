// Settings ▸ Documents & PDF (screens-flows.md §1.3, §2i, ADR 0010): the document defaults (payment term,
// footer), the PDF folder, automatic saving at issue, the year subfolder and the fixed file-name pattern.
// The folder is a security-scoped bookmark the user grants through the open panel; the app never writes
// anywhere else.

import AppKit
import InvoicingCore
import InvoicingData
import SwiftUI

struct DocumentsPane: View {
    let stores: Stores

    @State private var folderURL: URL?
    @State private var message: String?
    /// The stored profile; nil until the company is set up (the defaults need somewhere to live).
    @State private var profile: CompanyProfile?
    @State private var termDays = 14
    @State private var footer = ""
    @State private var defaultsMessage: LocalizedStringResource?
    @State private var defaultsError = false
    @AppStorage(PDFSettings.autoSaveKey) private var autoSave = true
    @AppStorage(PDFSettings.yearSubfolderKey) private var yearSubfolder = true
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                if profile != nil {
                    Stepper(value: $termDays, in: 0...365) {
                        LabeledContent { Text(verbatim: String(termDays)) } label: { Text(L.fieldDefaultTerm) }
                    }
                    TextField(text: $footer, axis: .vertical) { Text(L.fieldFooter) }
                        .lineLimit(2...4)
                    HStack {
                        if let defaultsMessage {
                            if defaultsError {
                                InlineMessage(defaultsMessage)
                            } else {
                                Text(defaultsMessage).textRole(.caption)
                            }
                        }
                        Spacer()
                        Button { saveDefaults() } label: { Text(L.save) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text(L.companyFirst).textRole(.body)
                }
            } header: {
                Text(L.documentDefaultsTitle)
            }
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
                    InlineMessage(message)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            folderURL = PDFSettings.folderURL()
            loadDefaults()
        }
    }

    private func loadDefaults() {
        profile = try? stores.profile.load()
        termDays = profile?.defaultPaymentTermDays ?? 14
        footer = profile?.footer ?? ""
    }

    private func saveDefaults() {
        guard var updated = profile else { return }
        let trimmedFooter = footer.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.defaultPaymentTermDays = termDays
        updated.footer = trimmedFooter.isEmpty ? nil : trimmedFooter
        do {
            try stores.profile.save(updated)
            profile = updated
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
            defaultsError = false
            defaultsMessage = L.saved
        } catch {
            defaultsError = true
            defaultsMessage = LocalizedStringResource(stringLiteral: ErrorText.message(error, locale: locale))
        }
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
