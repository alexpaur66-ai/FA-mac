import InvoicingCore

/// Errors of the data layer. A validation failure carries the issues so the UI can show them.
public enum DataError: Error, Equatable, Sendable {
    case documentNotFound(String)
    case customerNotFound(String)
    case seriesNotFound(String)
    case statementNotFound(String)
    case transactionNotFound(String)
    case paymentNotFound(String)
    /// The payment tax document issued for the payment rests on it; the payment cannot change or go.
    case paymentLocked(String)
    /// The document is not a payment tax document for exactly this payment.
    case receiptMismatch(paymentID: String, detail: String)
    /// Transactions of the statement are matched to documents; unmatch them first.
    case statementHasMatchedTransactions(id: String, count: Int)
    /// The document is issued; issued documents are never changed or deleted (§ 35 ZDPH).
    case documentIsFrozen(String)
    case documentAlreadyIssued(String)
    case documentNotIssued(String)
    /// Documents refer to the customer, so the record can only be archived.
    case customerHasDocuments(String)
    /// Errors (not warnings) the validator found; nothing was written.
    case validationFailed([ValidationIssue])
    /// An amount does not fit the integer minor units the database stores.
    case amountOutOfRange(String)
    /// A statement with the same file hash was imported before.
    case duplicateStatement(fileSHA256: String)
    /// A stored row cannot be read back as the value it was written from.
    case corruptRecord(table: String, id: String, detail: String)
    case currencyMismatch(expected: Currency, actual: Currency)
    /// The series does not number documents of this kind (its `kinds` do not include it).
    case seriesDoesNotNumber(seriesID: String, kind: DocumentKind)
    /// The payments taken from the bank transaction would exceed its credit; `available` is what is left
    /// of it (zero for a debit).
    case transactionOverallocated(id: String, available: Money, requested: Money)
    /// Payments were recorded from the transaction, so it cannot be unmatched or ignored; delete them first.
    case transactionHasPayments(String)
    /// `.automatic` and `.manual` need a document, `.unmatched` and `.ignored` take none.
    case invalidMatch(transactionID: String, state: TransactionMatchState)
    /// A payment or refund of zero, or an amount with the wrong sign.
    case invalidPaymentAmount(Money)
    /// A payment needs a credit line of the statement, a refund a debit line.
    case transactionDirectionMismatch(id: String)
    /// The overpaid document holds less credit than asked for.
    case creditNotAvailable(sourceDocumentID: String, available: Money, requested: Money)
    /// Applying the credit would overpay the target document.
    case creditExceedsOutstanding(targetDocumentID: String, outstanding: Money, requested: Money)
    /// The payment is one leg of an applied credit; the other leg is locked by its issued tax document.
    case relatedPaymentLocked(paymentID: String, relatedPaymentID: String)
    /// Only an advance request with nothing received can be closed as unpaid.
    case documentHasPayments(String)
    /// An issued final invoice deducted the advance; it cannot be closed as unpaid.
    case documentIsDeducted(String)
    case documentAlreadyClosed(String)
    case documentNotClosed(String)
    /// Closing as unpaid is for advance requests, marking for a credit note for tax documents.
    case closureNotApplicable(id: String, kind: DocumentKind)
    /// A closing event needs a reason.
    case reasonRequired
    /// A payment tax document is deducted by one final invoice only (§ 37a ZDPH).
    case advanceAlreadyDeducted(receiptNumber: String, by: String)
    /// The number a final invoice deducts belongs to a document that is not an issued payment tax document
    /// of the same customer and currency.
    case deductedDocumentInvalid(number: String, detail: String)
    /// A refund may not exceed what the document holds: its net paid amount or, for a final invoice whose
    /// advances exceed the supply, the credit the customer holds; `available` is that amount.
    case refundExceedsAvailable(documentID: String, available: Money, requested: Money)
    /// A payment tax document records money already received on its advance request; it takes no payments.
    case documentNotPayable(String)
    /// Credit moves only between documents of the same customer.
    case creditCustomerMismatch(sourceDocumentID: String, targetDocumentID: String)
    /// No PDF is stored for the document yet (`storePDF` first).
    case pdfNotStored(String)
    /// An issued final invoice settled the payment as paid in advance (§ 64 goods, ADR 0012): it cannot change
    /// or go, and it takes no payment tax document.
    case paymentSettled(paymentID: String, finalInvoiceNumber: String)
    /// An advance paid that a final invoice lists is not a payment received on an issued advance request of the
    /// final invoice's customer and currency, on that day and for at least that amount, without a tax document.
    case paidAdvanceInvalid(number: String, detail: String)
    /// A payment is settled as paid in advance by one final invoice only.
    case advanceAlreadySettled(advanceNumber: String, by: String)
    /// The advances paid listed for an advance request exceed what it holds: its payments net of refunds,
    /// less what other final invoices settled and what its payments with an issued payment tax document
    /// received (deducted under § 37a ZDPH instead); `available` is that amount.
    case paidAdvancesExceedPaid(advanceNumber: String, available: Money, listed: Money)
    /// The payment is one leg of an applied credit; an issued final invoice settled the other leg as paid in
    /// advance (ADR 0012), so the credit cannot go.
    case relatedPaymentSettled(paymentID: String, relatedPaymentID: String, finalInvoiceNumber: String)
    /// Issued final invoices settled payments of the advance request as paid in advance (ADR 0012), and
    /// deleting the payment would leave the advance holding less than they settled (with what its payments with
    /// an issued payment tax document received), or holding money no final invoice can list any more (a refund
    /// or credit moved away that a payment was settled net of). `finalInvoiceNumber` names the last of them.
    case paymentBacksSettlement(paymentID: String, finalInvoiceNumber: String)
    /// The bank line is matched to a document already, or a payment is taken from it; unmatch it first.
    case bankLineResolved(String)
    /// The payment is linked to a bank line already.
    case paymentAlreadyLinked(String)
    /// The payment cannot be confirmed by the bank line: another direction, another currency, or an amount
    /// outside the payment tolerance.
    case bankLineMismatch(transactionID: String, paymentID: String)
    /// The file is not a PDF.
    case notAPDF(String)
}
