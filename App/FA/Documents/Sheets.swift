// The small sheets of the document flow: Record Payment and Record Refund (with the tax-document step for
// advances), and the two closing events (ADR 0007).

import InvoicingCore
import InvoicingData
import SwiftUI

struct RecordPaymentSheet: View {
    enum Mode {
        /// Money received on the document.
        case payment
        /// The overpaid part paid back to the client (screens-flows.md §2f).
        case refund
    }

    let stores: Stores
    let state: DocumentState
    let mode: Mode
    /// The date of the payment last recorded in this window, proposed again; today when there is none.
    @Binding var lastDate: Date?
    /// Opens the draft payment tax document created for a payment on an advance (screens-flows.md §2d, step 2).
    let openDraft: @MainActor (String) -> Void
    /// Creates the final invoice of an advance for § 64 goods, which needs no tax document (ADR 0012).
    let createFinalInvoice: (@MainActor (String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var date: Date
    @State private var amount: Decimal?
    @State private var note = ""
    @State private var error: String?
    /// The payment just recorded on an advance request; it needs its own tax document.
    @State private var recorded: DocumentPayment?

    init(stores: Stores, state: DocumentState, mode: Mode, lastDate: Binding<Date?>, openDraft: @escaping @MainActor (String) -> Void,
         createFinalInvoice: (@MainActor (String) -> Void)? = nil) {
        self.stores = stores
        self.state = state
        self.mode = mode
        self._lastDate = lastDate
        self.openDraft = openDraft
        self.createFinalInvoice = createFinalInvoice
        _date = State(initialValue: min(lastDate.wrappedValue ?? Date(), Date()))
        // What is left to pay, or what was paid too much.
        let outstanding = state.outstanding.amount
        switch mode {
        case .payment: _amount = State(initialValue: outstanding > 0 ? outstanding : nil)
        case .refund: _amount = State(initialValue: outstanding < 0 ? -outstanding : nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(mode == .payment ? L.rpTitle : L.rpRefundTitle).textRole(.screenTitle)
            Text(verbatim: (state.summary.number ?? String(localized: L.draftTitle)) + " · " + state.summary.customerName)
                .textRole(.rowSecondary)
            if let recorded {
                recordedStep(recorded)
            } else {
                form
            }
        }
        .padding(Spacing.xl)
        .formSheetSized(minWidth: 460, maxWidth: 560)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Form {
                if mode == .refund {
                    Text(L.rpRefundNote).textRole(.caption)
                }
                // A payment lies in the past or today; the date picker refuses the future.
                DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) {
                    Text(mode == .payment ? L.rpDate : L.rpRefundDate)
                }
                MoneyField(amount: $amount, currency: state.summary.currency.code, label: L.rpAmount)
                TextField(text: $note) { Text(L.rpNote) }
                if let error {
                    InlineMessage(error)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { record() } label: { Text(mode == .payment ? L.rpRecord : L.rpRecordRefund) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(amount == nil)
            }
        }
    }

    /// Step 2 of the advance flow: the money is in, and the tax document for it is due within 15 days of
    /// the payment (§ 28 odst. 8 ZDPH). Create its draft now, or later with Create Tax Document in the
    /// payment's row of the advance's detail (the Overview queue selects that advance) or the Document menu.
    /// An advance for § 64 goods needs no tax document: the step offers its final invoice instead, which
    /// lists the payment as paid in advance (ADR 0012, the design thread's spec of 5 Nov 2026). An advance a
    /// final invoice already deducted or settled takes no payment (`DocumentState.acceptsPayment`), so the step
    /// never offers a second final invoice for the same supply.
    private func recordedStep(_ payment: DocumentPayment) -> some View {
        let goodsAdvance = !state.taxDocumentRequired
        return VStack(alignment: .leading, spacing: Spacing.l) {
            Label {
                Text(goodsAdvance ? L.paymentRecordedGoodsAdvance : L.paymentRecordedAdvance)
                    .textRole(.body).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let error {
                InlineMessage(error)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.later) }
                    .keyboardShortcut(.cancelAction)
                if goodsAdvance {
                    if let createFinalInvoice {
                        Button {
                            let advanceID = state.id
                            dismiss()
                            createFinalInvoice(advanceID)
                        } label: { Text(L.createFinalInvoice) }
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button { createTaxDocument(payment) } label: { Text(L.createTaxDocument) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func record() {
        guard let amount else { return }
        let day = CalendarDay(date, in: .current)
        let money = Money(amount, state.summary.currency)
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch mode {
            case .payment:
                let payment = try stores.documents.recordPayment(documentID: state.id, on: day, amount: money, note: text.isEmpty ? nil : text)
                lastDate = date
                if state.summary.kind == .advanceRequest {
                    error = nil
                    recorded = payment
                    return
                }
            case .refund:
                try stores.documents.recordRefund(documentID: state.id, on: day, amount: money, note: text.isEmpty ? nil : text)
                lastDate = date
            }
            dismiss()
        } catch {
            self.error = ErrorText.message(error, locale: locale)
        }
    }

    private func createTaxDocument(_ payment: DocumentPayment) {
        do {
            guard let id = try TaxDocumentDraft.create(stores: stores, advanceID: state.id, payment: payment) else { return }
            dismiss()
            openDraft(id)
        } catch {
            self.error = ErrorText.message(error, locale: locale)
        }
    }
}

/// The draft tax document for a payment received on an advance, linked to it at once (`attachReceipt`),
/// so the editor and the lists know which payment it records; the link is checked again when the draft
/// is issued. Used by Record Payment's last step and by Create Tax Document on a payment without one.
@MainActor enum TaxDocumentDraft {
    /// The new draft's id; nil when the advance no longer exists. A draft that cannot be linked is
    /// deleted again, so no unlinked tax document is left behind.
    static func create(stores: Stores, advanceID: String, payment: DocumentPayment) throws -> String? {
        guard let advance = try stores.documents.document(id: advanceID) else { return nil }
        let today = CalendarDay(Date(), in: .current)
        let receipt = Document.paymentTaxDocument(forAdvanceRequest: advance, received: payment.amount.amount,
                                                  on: payment.paidOn, issueDate: today)
        try stores.documents.saveDraft(receipt)
        do {
            try stores.documents.attachReceipt(paymentID: payment.id, documentID: receipt.id)
        } catch {
            try? stores.documents.deleteDraft(id: receipt.id)
            throw error
        }
        return receipt.id
    }

    /// The received payments of an advance that have no tax document yet, not even a draft.
    static func paymentsWithoutReceipt(_ payments: [DocumentPayment]) -> [DocumentPayment] {
        payments.filter { $0.kind == .received && $0.receiptDocumentID == nil }
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
            Text(L.closureExplanation).textRole(.body).fixedSize(horizontal: false, vertical: true)
            TextField(text: $reason, axis: .vertical) { Text(L.reasonPrompt) }
                .lineLimit(2...4)
            if let error {
                InlineMessage(error)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { close() } label: { Text(kind == .closedUnpaid ? L.closeAsUnpaidButton : L.markForCreditNoteButton) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .formSheetSized(minWidth: 460, maxWidth: 560)
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
