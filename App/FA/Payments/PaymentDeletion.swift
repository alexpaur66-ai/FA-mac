// Delete Payment with a draft tax document (ADR 0009 amendments): the draft documents nothing without
// its payment, so the dialog asks whether the draft goes too. Shared by the document detail and
// Payments; the window deletes and registers the undo.

import InvoicingData
import SwiftUI

struct PaymentDeletionDialog: ViewModifier {
    /// The payment waiting for the answer; nil hides the dialog.
    @Binding var pending: DocumentPayment?
    /// The payment, and whether its draft tax document is deleted with it.
    let delete: @MainActor (DocumentPayment, Bool) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            Text(L.deletePaymentWithDraftTitle),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { payment in
            Button(role: .destructive) { delete(payment, true) } label: { Text(L.deletePaymentAndDraft) }
            Button(role: .destructive) { delete(payment, false) } label: { Text(L.deletePaymentOnly) }
            Button(role: .cancel) {} label: { Text(L.cancel) }
        } message: { _ in
            Text(L.deletePaymentWithDraftMessage)
        }
    }
}

extension View {
    func paymentDeletionDialog(pending: Binding<DocumentPayment?>,
                               delete: @escaping @MainActor (DocumentPayment, Bool) -> Void) -> some View {
        modifier(PaymentDeletionDialog(pending: pending, delete: delete))
    }
}

extension DocumentPayment {
    /// Delete Payment is offered: the store refuses once the payment's tax document is issued.
    var canBeDeleted: Bool { !receiptIssued }

    /// A deletion that must be confirmed first: a draft tax document hangs on the payment.
    var deletionNeedsConfirmation: Bool { receiptDocumentID != nil && !receiptIssued }
}
