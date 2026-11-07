// Payments (screens-flows.md §2f): every recorded payment, newest first, with search. The bank import
// and the matching queue arrive with v0.2.

import InvoicingCore
import InvoicingData
import SwiftUI

struct PaymentRow: Identifiable, Hashable {
    let payment: DocumentPayment
    let state: DocumentState
    /// The final invoice that settled this payment as paid in advance (§ 64 goods, ADR 0012); nil otherwise.
    var settledIn: String? = nil

    var id: String { payment.id }
    var date: CalendarDay { payment.paidOn }
    var amount: Decimal { payment.amount.amount }
    var currencyCode: String { payment.amount.currency.code }
    var documentNumber: String { state.summary.number ?? "" }
    var customerName: String { state.summary.customerName }
    var note: String { payment.note ?? "" }
    /// An issued tax document rests on it, or a final invoice settled it as paid in advance (other-09).
    var isLocked: Bool { payment.receiptIssued || settledIn != nil }
    var canBeDeleted: Bool { payment.canBeDeleted && settledIn == nil }

    /// Plain search: client, document number, note and amount (screens-flows.md §2f).
    func matches(search: String) -> Bool {
        let needle = search.folded
        guard !needle.isEmpty else { return true }
        return [customerName, documentNumber, note, amount.description].contains { $0.folded.contains(needle) }
    }
}

struct PaymentsView: View {
    let stores: Stores
    let documents: DocumentListModel
    /// The document of the selected payment, for the detail column.
    @Binding var selectedDocumentID: String?
    /// Deletes a payment, and with it its draft tax document when the dialog says so; the window
    /// registers the undo.
    let deletePayment: @MainActor (DocumentPayment, Bool) -> Void
    /// Record Payment… on a document, from a statement read beside the open documents.
    let recordPayment: @MainActor (String) -> Void
    /// The window's result line.
    let report: @MainActor (String, ResultLineModel.Kind) -> Void

    @State private var rows: [PaymentRow] = []
    @State private var loaded = false
    @State private var loadError: String?
    /// Kept per window, so the selection survives a switch to another section (screens-flows.md §0.1).
    @SceneStorage("payments.selection") private var selection: String?
    @State private var paymentPendingDeletion: DocumentPayment?
    @State private var sortOrder = [KeyPathComparator(\PaymentRow.date, order: .reverse)]
    @State private var search = ""
    @Environment(\.locale) private var locale
    /// The statement read beside the open documents (PDF fallback, §2f); kept per window.
    @SceneStorage("payments.statement") private var openStatementID: String?
    @State private var statements: [BankStatement] = []
    @State private var importing = false
    /// A chosen statement file waiting for its account, when the profile has several.
    @State private var pendingFile: PendingStatementFile?
    @State private var accounts: [BankConnection] = []

    /// The rows the search leaves; the detail column, the menus and ⌫ act only on these, as in Documents.
    private var visibleRows: [PaymentRow] {
        rows.filter { $0.matches(search: search) }
    }

    var body: some View {
        Group {
            if let statement = statements.first(where: { $0.id == openStatementID }) {
                StatementReviewView(stores: stores, documents: documents, statement: statement,
                                    selectedDocumentID: $selectedDocumentID, recordPayment: recordPayment,
                                    close: { closeStatement() })
            } else {
                paymentsList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                StatementsMenu(statements: statements, open: { openStatement($0.id) }, importStatement: { importing = true })
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: StatementFileTypes.allowed, allowsMultipleSelection: false) { result in
            pick(result)
        }
        .confirmationDialog(Text(L.chooseStatementAccount), isPresented: pendingFileShown, presenting: pendingFile) { file in
            ForEach(accounts, id: \.iban) { account in
                Button { importFile(file, into: account) } label: { Text(verbatim: Self.accountName(account)) }
            }
        }
        .task { loadStatements() }
    }

    private var paymentsList: some View {
        VStack(spacing: 0) {
            if let loadError {
                HStack(spacing: Spacing.m) {
                    InlineMessage(loadError)
                    Spacer()
                    Button { load() } label: { Text(L.retry) }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                Divider()
            }
            if loaded && rows.isEmpty {
                ContentUnavailableView {
                    Label { Text(L.noPayments) } icon: { Image(systemName: "banknote") }
                } description: {
                    Text(L.noPaymentsDescription)
                }
            } else if loaded && visibleRows.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                table
            }
        }
        .navigationTitle(Text(L.payments))
        .navigationSubtitle(Text(verbatim: String(visibleRows.count)))
        .searchable(text: $search, placement: .toolbar, prompt: Text(L.searchPayments))
        .task(id: documents.states) {
            load()
        }
        .onChange(of: selection, initial: true) { _, newValue in
            sync(newValue)
        }
        // A selection the search hides is dropped, so nothing hidden is shown, deleted or acted on.
        .onChange(of: search) {
            dropHiddenSelection()
        }
        .paymentDeletionDialog(pending: $paymentPendingDeletion, delete: deletePayment)
    }

    // Date · Client · Document · Amount · Note (screens-flows.md §2f); Account, the CZK difference and the
    // Source arrive with the bank import, when statements make them differ from row to row.
    private var table: some View {
        Table(visibleRows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn(Text(L.colDate), value: \.date) { row in DayText(row.date) }
                .width(min: 90, ideal: 100)
            TableColumn(Text(L.colClient), value: \.customerName) { row in
                Text(verbatim: row.customerName.isEmpty ? String(localized: L.noClient) : row.customerName).textRole(.body)
            }
            TableColumn(Text(L.colDocument), value: \.documentNumber) { row in
                Text(verbatim: row.documentNumber).textRole(.body)
            }
            .width(min: 90, ideal: 130)
            TableColumn(Text(L.colAmount), value: \.amount) { row in
                HStack(spacing: Spacing.xs) {
                    MoneyText(amount: row.amount, currency: row.currencyCode, locale: locale)
                    if row.isLocked {
                        // The basis of an issued tax document, or settled in a final invoice: locked (other-09).
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel(Text(row.payment.receiptIssued ? L.paymentLocked : L.paymentSettledLocked))
                            .help(Text(row.payment.receiptIssued ? L.paymentLocked : L.paymentSettledLocked))
                    }
                }
            }
            .width(min: 110, ideal: 140)
            .alignment(.trailing)
            TableColumn(Text(L.colNote), value: \.note) { row in
                Text(verbatim: row.note).textRole(.body)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first, let row = visibleRows.first(where: { $0.id == id }), row.canBeDeleted {
                Button(role: .destructive) { requestDeletion(row.payment) } label: { Text(L.deletePayment) }
            }
        }
        .onDeleteCommand {
            if let id = selection, let row = visibleRows.first(where: { $0.id == id }), row.canBeDeleted {
                requestDeletion(row.payment)
            }
        }
    }

    // MARK: Statements

    private var pendingFileShown: Binding<Bool> {
        Binding(get: { pendingFile != nil }, set: { if !$0 { pendingFile = nil } })
    }

    private static func accountName(_ account: BankConnection) -> String {
        account.iban.formatted + (account.currency.map { " · " + $0.code } ?? "")
    }

    /// The payment selection is dropped first, so the detail column and ⌘R follow the statement's list.
    private func openStatement(_ id: String) {
        selection = nil
        selectedDocumentID = nil
        openStatementID = id
    }

    private func closeStatement() {
        selectedDocumentID = nil
        openStatementID = nil
    }

    private func loadStatements() {
        do {
            statements = try stores.statements.statements()
            if let id = openStatementID, !statements.contains(where: { $0.id == id }) { openStatementID = nil }
        } catch {
            report(ErrorText.message(error, locale: locale), .problem)
        }
    }

    /// Reads the chosen PDF; with one bank account it is imported at once, with several the account is asked.
    private func pick(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let file = PendingStatementFile(data: try Data(contentsOf: url), name: url.lastPathComponent)
            accounts = try stores.profile.load()?.bankConnections ?? []
            switch accounts.count {
            case 0: report(String(localized: L.statementNeedsAccount), .problem)
            case 1: importFile(file, into: accounts[0])
            default: pendingFile = file
            }
        } catch {
            report(ErrorText.message(error, locale: locale), .problem)
        }
    }

    private func importFile(_ file: PendingStatementFile, into account: BankConnection) {
        pendingFile = nil
        do {
            let currency = try account.currency ?? stores.profile.load()?.defaultCurrency ?? .czk
            let statement = try stores.statements.importPDF(file.data, fileName: file.name, iban: account.iban, currency: currency)
            loadStatements()
            openStatement(statement.id)
            report(String(localized: L.statementImported(file.name)), .done)
        } catch {
            report(ErrorText.message(error, locale: locale), .problem)
        }
    }

    private func requestDeletion(_ payment: DocumentPayment) {
        if payment.deletionNeedsConfirmation {
            paymentPendingDeletion = payment
        } else {
            deletePayment(payment, false)
        }
    }

    /// The selected payment's document; a selection the list no longer has is dropped once the list is loaded.
    private func sync(_ id: String?) {
        guard let id else {
            selectedDocumentID = nil
            return
        }
        if let row = rows.first(where: { $0.id == id }) {
            selectedDocumentID = row.state.id
        } else if loaded {
            selection = nil
        }
    }

    /// Drops a selected payment the search hides; `sync` then clears the detail column.
    private func dropHiddenSelection() {
        if let id = selection, !visibleRows.contains(where: { $0.id == id }) {
            selection = nil
        }
    }

    /// One query per issued document with a balance movement; a payments query across documents comes
    /// with the bank import.
    private func load() {
        var collected: [PaymentRow] = []
        do {
            for state in documents.states where state.summary.status == .issued {
                // Payments of a § 64 advance a final invoice settled as paid in advance are locked too. Every
                // issued advance is read: one with a pre-v3 payment tax document requires tax documents, yet
                // its other payments can still be listed (DocumentLinks.paidAdvanceLinks reads them the same way).
                var settled: [String: String] = [:]
                if state.summary.kind == .advanceRequest {
                    for link in try stores.documents.paidAdvances(ofAdvanceRequest: state.id) {
                        settled[link.paymentID] = link.finalInvoiceNumber
                    }
                }
                for payment in try stores.documents.payments(for: state.id) {
                    collected.append(PaymentRow(payment: payment, state: state, settledIn: settled[payment.id]))
                }
            }
            rows = collected
            loadError = nil
        } catch {
            rows = collected
            loadError = ErrorText.message(error, locale: locale)
        }
        loaded = documents.loaded
        sync(selection)
        if loaded { dropHiddenSelection() }
    }
}

/// A statement file read from disk, waiting for the account it belongs to.
struct PendingStatementFile: Identifiable {
    let id = UUID()
    let data: Data
    let name: String
}
