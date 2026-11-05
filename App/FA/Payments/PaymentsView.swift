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
    var kindName: String { String(localized: payment.kind.title) }
    var documentNumber: String { state.summary.number ?? "" }
    var customerName: String { state.summary.customerName }
    var note: String { payment.note ?? "" }
}

struct PaymentsView: View {
    let stores: Stores
    let documents: DocumentListModel
    @Binding var selectedDocumentID: String?

    @State private var rows: [PaymentRow] = []
    @State private var loadError: String?
    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\PaymentRow.date, order: .reverse)]
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label { Text(L.noPayments) } icon: { Image(systemName: "banknote") }
                } description: {
                    if let loadError { Text(verbatim: loadError) } else { EmptyView() }
                }
            } else {
                Table(rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                    TableColumn(Text(L.colDate), value: \.date) { row in DayText(row.date) }
                        .width(min: 90, ideal: 100)
                    TableColumn(Text(L.colKind), value: \.kindName)
                        .width(min: 80, ideal: 110)
                    TableColumn(Text(L.colAmount), value: \.amount) { row in
                        MoneyText(amount: row.amount, currency: row.currencyCode, locale: locale)
                    }
                    .width(min: 100, ideal: 130)
                    .alignment(.trailing)
                    TableColumn(Text(L.colDocument), value: \.documentNumber)
                        .width(min: 90, ideal: 130)
                    TableColumn(Text(L.colClient), value: \.customerName)
                    TableColumn(Text(L.colNote), value: \.note)
                }
            }
        }
        .navigationTitle(Text(L.payments))
        .navigationSubtitle(Text(verbatim: String(rows.count)))
        .task(id: documents.states) {
            load()
        }
        .onChange(of: selection) { _, newValue in
            selectedDocumentID = rows.first { $0.id == newValue }?.state.id
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
            loadError = ErrorText.message(error)
        }
    }
}
