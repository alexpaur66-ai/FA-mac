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
}
