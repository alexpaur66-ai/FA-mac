// The detail column for one document: the issued view (read-only header, lock line, payments, the
// prominent Record Payment), or the draft placeholder until the editor arrives (screens-flows.md §2b).

import InvoicingCore
import InvoicingData
import SwiftUI

struct DocumentDetailView: View {
    let stores: Stores
    let documents: DocumentListModel
    let documentID: String
    let recordPayment: @MainActor (String) -> Void
    let deleteDraft: @MainActor (String) -> Void

    @State private var payments: [DocumentPayment] = []
    @State private var loadError: String?
    @Environment(\.locale) private var locale

    private struct LoadKey: Equatable {
        let id: String
        let states: [DocumentState]
    }

    var body: some View {
        ScrollView {
            if let state = documents.state(id: documentID) {
                content(state)
                    .padding(Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView {
                    Label { Text(L.noSelection) } icon: { Image(systemName: Symbols.document) }
                }
            }
        }
        .navigationTitle(Text(verbatim: documents.state(id: documentID)?.summary.number ?? String(localized: L.draftTitle)))
        .task(id: LoadKey(id: documentID, states: documents.states)) {
            load()
        }
    }

    private func load() {
        do {
            payments = try stores.documents.payments(for: documentID)
            loadError = nil
        } catch {
            payments = []
            loadError = String(describing: error)
        }
    }

    @ViewBuilder private func content(_ state: DocumentState) -> some View {
        let summary = state.summary
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header(state)
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
                GridRow {
                    Text(L.colTotal).textRole(.label)
                    MoneyText(amount: summary.totalGross?.amount ?? 0, currency: summary.currency.code, locale: locale, role: .total)
                }
                if summary.status == .issued && summary.kind != .paymentTaxDocument {
                    GridRow {
                        Text(L.paid).textRole(.label)
                        MoneyText(amount: state.paid.amount, currency: summary.currency.code, locale: locale)
                    }
                    GridRow {
                        Text(L.outstanding).textRole(.label)
                        MoneyText(amount: state.outstanding.amount, currency: summary.currency.code, locale: locale, role: .amountStrong)
                    }
                }
                GridRow {
                    Text(L.issuedOn).textRole(.label)
                    DayText(summary.issueDate)
                }
                GridRow {
                    Text(L.dueOn).textRole(.label)
                    DayText(summary.dueDate)
                }
                if let symbol = summary.variableSymbol {
                    GridRow {
                        Text(L.variableSymbol).textRole(.label)
                        Text(verbatim: symbol).textRole(.amount).textSelection(.enabled)
                    }
                }
                if !state.deductedBy.isEmpty {
                    GridRow {
                        Text(L.chain).textRole(.label)
                        Text(L.deductedBy(state.deductedBy.joined(separator: ", "))).textRole(.body)
                    }
                }
            }
            if summary.status == .issued {
                Label {
                    Text(L.lockLine(summary.issueDate.formatted(locale)))
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .textRole(.legalNote)
            } else {
                Text(L.draftNote).textRole(.body)
            }
            if let closure = state.closure {
                closureLine(closure)
            }
            if summary.status == .issued {
                paymentsSection
            }
            actions(state)
            if let loadError {
                Text(verbatim: loadError).textRole(.caption).foregroundStyle(.red)
            }
        }
    }

    private func header(_ state: DocumentState) -> some View {
        let summary = state.summary
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: summary.number ?? String(localized: L.draftTitle)).textRole(.documentNumber)
                Text(verbatim: summary.kind.title(language: .ui(locale))).textRole(.body)
                Text(verbatim: summary.customerName.isEmpty ? String(localized: L.noClient) : summary.customerName)
                    .textRole(.rowSecondary)
            }
            Spacer(minLength: Spacing.l)
            StatusBadge(DocumentStateInputs(state), detail: DocumentRow(state: state).badgeDetail(locale: locale))
        }
    }

    private func closureLine(_ closure: DocumentClosure) -> some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                StatusBadge(closure.kind == .closedUnpaid ? DocumentStateLabel.closedUnpaid : DocumentStateLabel.markedForCreditNote)
                Text(verbatim: String(localized: L.closureReason) + ": " + closure.reason).textRole(.rowSecondary)
            }
        } icon: {
            Image(systemName: closure.kind == .closedUnpaid ? "xmark.circle" : "flag")
        }
    }

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.paymentsSection).textRole(.sectionTitle)
            if payments.isEmpty {
                Text(L.noPayments).textRole(.rowSecondary)
            }
            ForEach(payments) { payment in
                HStack(spacing: Spacing.m) {
                    DayText(payment.paidOn)
                    Text(payment.kind.title).textRole(.rowSecondary)
                    if let note = payment.note, !note.isEmpty {
                        Text(verbatim: note).textRole(.rowSecondary).lineLimit(1)
                    }
                    Spacer()
                    MoneyText(amount: payment.amount.amount, currency: payment.amount.currency.code, locale: locale)
                    if payment.receiptIssued {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .help(Text(L.paymentLocked))
                    }
                }
                .contextMenu {
                    if !payment.receiptIssued {
                        Button(role: .destructive) { deletePayment(payment.id) } label: { Text(L.delete) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func actions(_ state: DocumentState) -> some View {
        HStack(spacing: Spacing.m) {
            if state.summary.status == .draft {
                Button(role: .destructive) { deleteDraft(documentID) } label: { Text(L.deleteDraft) }
            } else if state.summary.kind != .paymentTaxDocument && state.closure?.kind != .closedUnpaid {
                Button { recordPayment(documentID) } label: {
                    Label { Text(L.recordPayment) } icon: { Image(systemName: "banknote") }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func deletePayment(_ id: String) {
        do {
            try stores.documents.deletePayment(id: id)
            load()
        } catch {
            loadError = String(describing: error)
        }
    }
}

/// The inspector: derived information only (design-system.md §8.12): payment details, payments,
/// the document chain and the activity log.
struct DocumentInspectorView: View {
    let stores: Stores
    let documents: DocumentListModel
    let documentID: String

    @State private var document: Document?
    @State private var payments: [DocumentPayment] = []
    @State private var events: [AuditEvent] = []
    @Environment(\.locale) private var locale

    private struct LoadKey: Equatable {
        let id: String
        let states: [DocumentState]
    }

    var body: some View {
        List {
            if let payment = document?.payment {
                Section {
                    LabeledContent { Text(verbatim: payment.bankConnection.iban.formatted).textSelection(.enabled) } label: { Text(L.account) }
                    if let symbol = payment.variableSymbol {
                        LabeledContent { Text(verbatim: symbol.digits).textSelection(.enabled) } label: { Text(L.variableSymbol) }
                    }
                } header: {
                    Text(L.paymentDetails)
                }
            }
            Section {
                if payments.isEmpty {
                    Text(L.noPayments).textRole(.rowSecondary)
                }
                ForEach(payments) { payment in
                    LabeledContent {
                        Text(verbatim: MoneyText.format(payment.amount.amount, currency: payment.amount.currency.code, locale: locale))
                    } label: {
                        Text(verbatim: payment.paidOn.formatted(locale) + " · " + String(localized: payment.kind.title))
                    }
                }
            } header: {
                Text(L.paymentsSection)
            }
            if let state = documents.state(id: documentID), !state.deductedBy.isEmpty {
                Section {
                    ForEach(state.deductedBy, id: \.self) { number in
                        Text(verbatim: number)
                    }
                } header: {
                    Text(L.chain)
                }
            }
            Section {
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: event.action).textRole(.body)
                        Text(verbatim: Self.timestamp(event.at, locale: locale)).textRole(.caption)
                    }
                }
            } header: {
                Text(L.activity)
            }
        }
        .task(id: LoadKey(id: documentID, states: documents.states)) {
            document = try? stores.documents.document(id: documentID)
            payments = (try? stores.documents.payments(for: documentID)) ?? []
            events = (try? stores.audit.events(entity: "document", id: documentID)) ?? []
        }
    }

    /// The stored ISO 8601 timestamp in the UI locale; the raw text when it cannot be parsed.
    private static func timestamp(_ iso: String, locale: Locale) -> String {
        guard let date = try? Date(iso, strategy: .iso8601) else { return iso }
        return date.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: locale))
    }
}
