// File ▸ Export for Accountant… (screens-flows.md §2h): the month bar on the previous month, what the month
// holds, whether it was exported, and one button. The save panel proposes a folder "FA 2026-10" in the
// last export's folder; a backup runs first, then the Documents and Payments CSVs are written into that
// folder and the month's export record is kept. The main window's result line reports it.

import AppKit
import InvoicingCore
import InvoicingData
import SwiftUI

struct AccountantExportSheet: View {
    let stores: Stores
    /// The result line: its text, and whether it reports a problem (the backup failed).
    let onExported: @MainActor (String, Bool) -> Void

    @State private var month: CalendarDay
    @State private var data: AccountantExportData?
    @State private var record: MonthExport?
    @State private var changedCount = 0
    @State private var error: String?
    @State private var exporting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// `month` nil opens on the previous month (§2h); the Overview's Export Again… passes its month.
    init(stores: Stores, month: CalendarDay?, onExported: @escaping @MainActor (String, Bool) -> Void) {
        self.stores = stores
        self.onExported = onExported
        let previous = CalendarDay(Date(), in: .current).startOfMonth.adding(months: -1).startOfMonth
        _month = State(initialValue: month?.startOfMonth ?? previous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L.exportTitle).textRole(.screenTitle)
            MonthBar(month: $month)
            if let data {
                Text(verbatim: previewText(data)).textRole(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: " ").textRole(.body)
            }
            Text(verbatim: statusText)
                .textRole(.rowSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let error {
                InlineMessage(error)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { export() } label: { Text(buttonTitle) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(data == nil || exporting)
            }
        }
        .padding(Spacing.xl)
        .formSheetSized(minWidth: 480, maxWidth: 620)
        .task(id: month) { load() }
    }

    private var monthTitle: String { MonthBar.title(month, locale: locale) }

    private var buttonTitle: LocalizedStringResource {
        record == nil ? L.exportButton(monthTitle) : L.exportAgainButton(monthTitle)
    }

    private func load() {
        error = nil
        do {
            data = try stores.exports.data(month: month, today: CalendarDay(Date(), in: .current))
            record = try stores.exports.record(month: month)
            changedCount = try stores.exports.changedAfterExport().first { $0.export.month == month.startOfMonth }?.changedCount ?? 0
        } catch {
            data = nil
            record = nil
            changedCount = 0
            self.error = ErrorText.message(error, locale: locale)
        }
    }

    /// "October 2026: 14 documents (2 advances, non-tax) · 9 payments · VAT 42 180 Kč".
    private func previewText(_ data: AccountantExportData) -> String {
        var documents = Count.documents(data.documents.count)
        switch data.advanceCount {
        case 0: break
        case 1: documents = String(localized: L.exportDocumentsWithAdvanceOne(documents))
        default: documents = String(localized: L.exportDocumentsWithAdvances(documents, data.advanceCount))
        }
        let payments = data.payments.count == 1
            ? String(localized: L.exportPaymentsOne) : String(localized: L.exportPaymentsCount(data.payments.count))
        let vat = MoneyText.format(data.vatCZK, currency: "CZK", locale: locale)
        return String(localized: L.exportPreview(monthTitle, documents, payments, vat))
    }

    /// "Not exported yet", or "Exported on 3. 11. 2026 to ~/…/FA 2026-10 · 1 document changed after export".
    private var statusText: String {
        guard let record else { return String(localized: L.exportNotYet) }
        let day = AccountantExportFiles.exportDay(record).map { $0.formatted(locale) } ?? record.exportedAt
        var text = String(localized: L.exportedOnTo(day, AccountantExportFiles.displayPath(record.folder)))
        if changedCount > 0 {
            text += " · " + AccountantExportFiles.changedText(changedCount)
        }
        return text
    }

    /// ↩: the save panel, then the backup, then the files (§2h). A backup that fails doesn't stop the export;
    /// files that can't be written leave the month unmarked and the sheet open with the reason.
    private func export() {
        error = nil
        let lastFolder = try? stores.exports.lastFolder()
        guard let folder = AccountantExportFiles.chooseFolder(month: month, lastFolder: lastFolder) else { return }
        exporting = true
        defer { exporting = false }
        let backup = BackupService.backUp(stores)
        do {
            // Read again after the panel: the export holds what is stored when it is written.
            let fresh = try stores.exports.data(month: month, today: CalendarDay(Date(), in: .current))
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            try stores.exports.write(fresh, labels: .app, to: folder)
            NotificationCenter.default.post(name: .monthExported, object: nil)
        } catch {
            // load() clears the message, so it comes after the re-read.
            let message = String(localized: L.exportFailed(ErrorText.message(error, locale: locale)))
            load()
            self.error = message
            return
        }
        let name = monthTitle
        switch backup {
        case .success?:
            onExported(String(localized: L.exportDoneBackup(name)), false)
        case .failure(let failure)?:
            onExported(String(localized: L.exportDoneBackupFailed(name, ErrorText.message(failure, locale: locale))), true)
        case nil:
            onExported(String(localized: L.exportDone(name)), false)
        }
        dismiss()
    }
}

/// The save panel and the words around an export record, shared by the sheet and the Overview's queue row.
@MainActor
enum AccountantExportFiles {
    /// A save panel for the month's folder, "FA 2026-10", in the folder of the last export; nil when cancelled.
    static func chooseFolder(month: CalendarDay, lastFolder: String?) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = AccountantCSV.folderName(month)
        panel.canCreateDirectories = true
        panel.prompt = String(localized: L.exportPanelPrompt)
        panel.message = String(localized: L.exportPanelMessage)
        if let lastFolder {
            panel.directoryURL = URL(fileURLWithPath: lastFolder, isDirectory: true).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    /// The local day of the export.
    static func exportDay(_ record: MonthExport) -> CalendarDay? {
        guard let date = try? Date(record.exportedAt, strategy: .iso8601) else { return nil }
        return CalendarDay(date, in: .current)
    }

    /// "1 document changed after export".
    static func changedText(_ count: Int) -> String {
        count == 1 ? String(localized: L.exportChangedOne) : String(localized: L.exportChangedCount(count))
    }

    /// The folder with the home folder as "~". The sandbox's home is the app's container, so the user's own
    /// home comes from the user database.
    static func displayPath(_ path: String) -> String {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return path }
        let home = String(cString: directory)
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

extension Notification.Name {
    /// A month was exported for the accountant: the Overview's export rows read the records again.
    static let monthExported = Notification.Name("FA.monthExported")
}

extension AccountantExportLabels {
    /// The app's own words, so the CSV says what the badges and the payment rows say (design-system.md §9).
    static var app: AccountantExportLabels {
        AccountantExportLabels(
            status: { state in String(localized: DocumentStateInputs(state).label.style.label) },
            paymentKind: { kind in String(localized: kind.title) },
            paymentSource: { payment in String(localized: payment.sourceTitle) },
            closure: { kind in
                switch kind {
                case .closedUnpaid: String(localized: DocumentStateLabel.closedUnpaid.style.label)
                case .markedForCreditNote: String(localized: DocumentStateLabel.markedForCreditNote.style.label)
                }
            },
            rateSource: { source in RateSourceName.text(source) })
    }
}
