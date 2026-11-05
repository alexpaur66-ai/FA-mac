// The small sheets of the document flow: Record Payment (with the tax-document step for advances), and
// the two closing events (ADR 0007).

import InvoicingCore
import InvoicingData
import SwiftUI

struct RecordPaymentSheet: View {
    let stores: Stores
    let state: DocumentState
    /// Opens the draft payment tax document created for a payment on an advance (screens-flows.md §2d, step 2).
    let openDraft: @MainActor (String) -> Void

    private enum Entry: Hashable {
        case received, refund
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var date = Date()
    @State private var amount: Decimal
    @State private var entry: Entry = .received
    @State private var note = ""
    @State private var error: String?
    /// The payment just recorded on an advance request; it needs its own tax document.
    @State private var recorded: DocumentPayment?

    init(stores: Stores, state: DocumentState, openDraft: @escaping @MainActor (String) -> Void) {
        self.stores = stores
        self.state = state
        self.openDraft = openDraft
        _amount = State(initialValue: state.outstanding.amount > 0 ? state.outstanding.amount : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L.rpTitle).textRole(.screenTitle)
            Text(verbatim: (state.summary.number ?? String(localized: L.draftTitle)) + " · " + state.summary.customerName)
                .textRole(.rowSecondary)
            if let recorded {
                recordedStep(recorded)
            } else {
                form
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 440)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Form {
                if state.settlement == .overpaid {
                    Picker(selection: $entry) {
                        Text(L.paymentReceived).tag(Entry.received)
                        Text(L.paymentRefund).tag(Entry.refund)
                    } label: {
                        Text(L.rpKind)
                    }
                    .pickerStyle(.segmented)
                }
                DatePicker(selection: $date, displayedComponents: .date) { Text(L.rpDate) }
                TextField(value: $amount, format: Decimal.FormatStyle.number.precision(.fractionLength(0...2))) {
                    Text(L.rpAmount)
                }
                TextField(text: $note) { Text(L.rpNote) }
                if let error {
                    Text(verbatim: error).textRole(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { record() } label: { Text(L.rpRecord) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(amount <= 0)
            }
        }
    }

    /// Step 2 of the advance flow: the money is in, and the tax document for it is due within 15 days of
    /// the payment (§ 28 odst. 8 ZDPH). Create its draft now, or later from the Overview queue.
    private func recordedStep(_ payment: DocumentPayment) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Label {
                Text(L.paymentRecordedAdvance).textRole(.body).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let error {
                Text(verbatim: error).textRole(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.later) }
                    .keyboardShortcut(.cancelAction)
                Button { createTaxDocument(payment) } label: { Text(L.createTaxDocument) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func record() {
        let day = CalendarDay(date, in: .current)
        let money = Money(amount, state.summary.currency)
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch entry {
            case .received:
                let payment = try stores.documents.recordPayment(documentID: state.id, on: day, amount: money, note: text.isEmpty ? nil : text)
                if state.summary.kind == .advanceRequest {
                    error = nil
                    recorded = payment
                    return
                }
            case .refund:
                try stores.documents.recordRefund(documentID: state.id, on: day, amount: money, note: text.isEmpty ? nil : text)
            }
            dismiss()
        } catch {
            self.error = ErrorText.message(error, locale: locale)
        }
    }

    /// The draft tax document for the payment, linked to it at once (`attachReceipt`), so the editor and
    /// the lists know which payment it records; the link is checked again when the draft is issued.
    private func createTaxDocument(_ payment: DocumentPayment) {
        do {
            guard let advance = try stores.documents.document(id: state.id) else { return }
            let today = CalendarDay(Date(), in: .current)
            let receipt = Document.paymentTaxDocument(forAdvanceRequest: advance, received: payment.amount.amount,
                                                      on: payment.paidOn, issueDate: today)
            try stores.documents.saveDraft(receipt)
            try stores.documents.attachReceipt(paymentID: payment.id, documentID: receipt.id)
            dismiss()
            openDraft(receipt.id)
        } catch {
            self.error = ErrorText.message(error, locale: locale)
        }
    }
}

/// Close Advance as Unpaid… / Mark for Credit Note…: a reason, recorded beside the frozen document.
struct ClosureSheet: View {
    let stores: Stores
    let state: DocumentState
    let kind: DocumentClosureKind

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var reason = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(kind == .closedUnpaid ? L.closeAdvanceTitle : L.markForCreditNoteTitle).textRole(.screenTitle)
            Text(verbatim: (state.summary.number ?? "") + " · " + state.summary.customerName).textRole(.rowSecondary)
            Text(L.closureExplanation).textRole(.body)
            TextField(text: $reason, axis: .vertical) { Text(L.reasonPrompt) }
                .lineLimit(2...4)
            if let error {
                Text(verbatim: error).textRole(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { close() } label: { Text(L.save) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 440)
    }

    private func close() {
        do {
            switch kind {
            case .closedUnpaid:
                try stores.documents.closeAdvanceUnpaid(id: state.id, reason: reason)
            case .markedForCreditNote:
                try stores.documents.markForCreditNote(id: state.id, reason: reason)
            }
            dismiss()
        } catch {
            self.error = ErrorText.message(error, locale: locale)
        }
    }
}
