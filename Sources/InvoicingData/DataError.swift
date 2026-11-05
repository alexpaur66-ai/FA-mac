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
}
