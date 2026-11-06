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
    /// Advance requests: each payment received needs a payment tax document. False for an issued advance
    /// whose lines are all § 64 goods, which a final invoice settles as paid in advance instead (ADR 0012),
    /// unless a payment of it already has a payment tax document (a draft or an issued one, from before v3):
    /// such an advance keeps that flow. True for every other one until the customer setting exists
    /// (screens-flows.md §6, question 5).
    public let taxDocumentRequired: Bool
    /// Advance requests: at least one payment was received and every received payment has an issued
    /// payment tax document.
    public let taxDocumentIssued: Bool
    /// Advance requests: an issued final invoice deducted a payment tax document of this advance, or settled
    /// one of its payments as paid in advance (§ 64 goods, ADR 0012).
    public let deductedInFinal: Bool
    /// Numbers of the final invoices that deducted or settled this advance, each once; usually one.
    public let deductedBy: [String]
    /// The closing event, if any (`closedUnpaid` or `markedForCreditNote`).
    public let closure: DocumentClosure?

    public var id: String { summary.id }
    public var markedForCreditNote: Bool { closure?.kind == .markedForCreditNote }
}

extension DocumentState {
    /// Record Payment… applies: an issued document with an open balance that is not a payment tax document
    /// (the store refuses those) and has no closing event. An advance that an issued final invoice deducted
    /// or settled as paid in advance takes none: money that arrives later is recorded on the final invoice,
    /// so it cannot change what the final invoice counted (the design thread's lean pass, ADR 0012). Shared
    /// by the toolbar, the context menu, the menu bar and the bank matching.
    public var acceptsPayment: Bool {
        takesIncomingPayment && outstanding.amount > 0
    }

    /// Record Refund… applies: an overpaid document gives the surplus back (screens-flows.md §2f).
    public var acceptsRefund: Bool {
        summary.status == .issued && summary.kind != .paymentTaxDocument && closure == nil && outstanding.amount < 0
    }

    /// Money may still arrive on it, as a payment or an overpayment: `acceptsPayment` without the open balance.
    var takesIncomingPayment: Bool {
        summary.status == .issued && summary.kind != .paymentTaxDocument && closure == nil && !deductedInFinal
    }
}
