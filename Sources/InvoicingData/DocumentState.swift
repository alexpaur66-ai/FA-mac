import Foundation
import InvoicingCore

/// How far a document is paid (ADR 0007). The raw values match the settlement axis of the design
/// system's `DocumentStateInputs`, so the app maps one to the other by raw value.
public enum DocumentSettlement: String, Sendable, CaseIterable {
    case draft
    /// Issued, nothing received.
    case open
    case partlyPaid
    case paid
    /// More received than due; the customer holds the difference as credit (`DocumentStore.applyCredit`,
    /// `recordRefund`). A final invoice whose advances exceed its supply reads the same way.
    case overpaid
    /// A final invoice whose deducted advances cover the whole amount due.
    case settledByAdvances
    /// An advance request closed without payment (`DocumentStore.closeAdvanceUnpaid`).
    case closedUnpaid
}

/// Everything a list row or a status badge needs about a stored document, computed as of `today` from
/// the document row, its payments, its closing event and the deduction links. The design system's
/// `DocumentStateInputs` is filled from it field by field.
public struct DocumentState: Hashable, Sendable, Identifiable {
    public let summary: DocumentSummary
    public let settlement: DocumentSettlement
    /// Net sum of the payments: received and credit in, minus refunds and credit out. Zero on a draft. On
    /// an issued payment tax document, the payment it records (its amount due; the payment itself is booked
    /// on the advance request).
    public let paid: Money
    /// Amount due minus `paid`; negative when overpaid. Zero on a draft and on an issued payment tax document.
    public let outstanding: Money
    /// Issued, past the due date, open or partly paid, and not closed. Payment tax documents are never
    /// overdue: they record money already received.
    public let isOverdue: Bool
    /// Days since the due date while overdue, otherwise 0.
    public let daysOverdue: Int
    /// Advance requests: the customer's advances need a payment tax document for each payment received.
    /// True for every customer until the customer setting exists (screens-flows.md §6, question 5).
    public let taxDocumentRequired: Bool
    /// Advance requests: at least one payment was received and every received payment has an issued
    /// payment tax document.
    public let taxDocumentIssued: Bool
    /// Advance requests: an issued final invoice deducted a payment tax document of this advance.
    public let deductedInFinal: Bool
    /// Numbers of the final invoices that deducted this advance, each once; usually one.
    public let deductedBy: [String]
    /// The closing event, if any (`closedUnpaid` or `markedForCreditNote`).
    public let closure: DocumentClosure?

    public var id: String { summary.id }
    public var markedForCreditNote: Bool { closure?.kind == .markedForCreditNote }
}
