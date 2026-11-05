// Payments & Bank (screens-flows.md §2f): every recorded payment, newest first. The bank import and the
// matching queue arrive with v0.2.

import InvoicingCore
import InvoicingData
import SwiftUI

struct PaymentRow: Identifiable, Hashable {
    let payment: DocumentPayment
    let state: DocumentState

    var id: String { payment.id }
    var date: CalendarDay { payment.paidOn }
    var amount: Decimal { payment.amount.amount }
    var currencyCode: String { payment.amount.currency.code }
    /// Typed, Statement or Credit (screens-flows.md §2f).
    var sourceName: String { String(localized: payment.sourceTitle) }
    var documentNumber: String { state.summary.number ?? "" }
    var customerName: String { state.summary.customerName }
    var note: String { payment.note ?? "" }
}

struct PaymentsView: View {
    let stores: Stores
    let documents: DocumentListModel
    /// The document of the selected payment, for the detail column and the inspector.
    @Binding var selectedDocumentID: String?
    /// Deletes a payment (a draft tax document never goes with it from here); the window registers the undo.
    let deletePayment: @MainActor (DocumentPayment) -> Void

    @State private var rows: [PaymentRow] = []
    @State private var loaded = false
    @State private var loadError: String?
    /// Kept per window, so the selection survives a switch to another section (screens-flows.md §0.1).
    @SceneStorage("payments.selection") private var selection: String?
    @State private var paymentPendingDeletion: DocumentPayment?
    @State private var sortOrder = [KeyPathComparator(\PaymentRow.date, order: .reverse)]
    @Environment(\.locale) private var locale

    var body: some View {
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
            } else {
                table
            }
        }
        .navigationTitle(Text(L.payments))
        .navigationSubtitle(Text(verbatim: String(rows.count)))
        .task(id: documents.states) {
            load()
        }
        .onChange(of: selection, initial: true) { _, newValue in
            sync(newValue)
        }
        .paymentDeletionDialog(pending: $paymentPendingDeletion) { payment, _ in
            deletePayment(payment)
        }
    }

    // Date · Client · Document · Amount · Source · Note (screens-flows.md §2f); Account and the CZK
    // difference arrive with the bank import.
    private var table: some View {
        Table(rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
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
                    if row.payment.receiptIssued {
                        // The basis of an issued tax document: locked (screens-flows.md §2f).
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel(Text(L.paymentLocked))
                    }
                }
            }
            .width(min: 110, ideal: 140)
            .alignment(.trailing)
            TableColumn(Text(L.colSource), value: \.sourceName) { row in
                Text(verbatim: row.sourceName).textRole(.body)
            }
            .width(min: 70, ideal: 90)
            TableColumn(Text(L.colNote), value: \.note) { row in
                Text(verbatim: row.note).textRole(.body)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first, let row = rows.first(where: { $0.id == id }), row.payment.canBeDeleted {
                Button(role: .destructive) { requestDeletion(row.payment) } label: { Text(L.deletePayment) }
            }
        }
        .onDeleteCommand {
            if let id = selection, let row = rows.first(where: { $0.id == id }), row.payment.canBeDeleted {
                requestDeletion(row.payment)
            }
        }
    }

    private func requestDeletion(_ payment: DocumentPayment) {
        if payment.deletionNeedsConfirmation {
            paymentPendingDeletion = payment
        } else {
            deletePayment(payment)
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

    /// One query per issued document with a balance movement; a payments query across documents comes
    /// with the bank import.
    private func load() {
        var collected: [PaymentRow] = []
        do {
            for state in documents.states where state.summary.status == .issued {
                for payment in try stores.documents.payments(for: state.id) {
                    collected.append(PaymentRow(payment: payment, state: state))
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
    }
}
