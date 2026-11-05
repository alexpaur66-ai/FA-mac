// Status styles: tone, SF Symbol and label for every document state and bank match state.
// Specification: docs/design/design-system.md §4.3. Status is always symbol + word; colour only reinforces it.
// Labels live in the "DesignSystem" string table (DesignSystem.xcstrings), English and Czech.

import SwiftUI

// MARK: - Tone

/// The colour family of a status. Orange means "the amount doesn't match, or a step is missing;
/// decide something". Red is only for Overdue.
enum StatusTone: CaseIterable, Sendable {
    case neutral, pending, caution, success, danger

    /// SwiftUI system colours, which carry their own dark and increased-contrast variants.
    var tint: Color {
        switch self {
        case .neutral: return .secondary
        case .pending: return .primary
        case .caution: return .orange
        case .success: return .green
        case .danger: return .red
        }
    }
}

/// What a badge draws: tone, symbol and the localized word.
struct StatusStyle {
    let tone: StatusTone
    let symbol: String
    let label: LocalizedStringResource
}

// MARK: - Document state

/// The facts a document's badge is computed from. The data layer fills it from the InvoicingCore
/// document and its payments; the views only display the result.
///
/// Two independent axes: `settlement` and `isOverdue`. Overdue never replaces the settlement. It wins
/// the tone and symbol, and the badge detail keeps the open balance ("+12 dní · zbývá 1 000,00 €").
struct DocumentStateInputs: Hashable, Sendable {
    /// The document type. The raw values match `InvoicingCore.DocumentKind`, so the data layer can map
    /// one to the other with `Kind(rawValue:)`.
    enum Kind: String, CaseIterable, Sendable {
        /// Faktura – daňový doklad.
        case invoice
        /// Zálohová faktura (výzva k platbě).
        case advanceRequest
        /// Daňový doklad k přijaté platbě (DDPP).
        case paymentTaxDocument
        /// Konečná faktura (vyúčtování záloh).
        case finalInvoice
    }

    /// Axis 1. `open` means issued with nothing paid. `settledByAdvances` is a final invoice whose
    /// amount due is 0. `closedUnpaid` is an advance request closed without payment.
    enum Settlement: String, CaseIterable, Sendable {
        case draft, open, partlyPaid, paid, overpaid, settledByAdvances, closedUnpaid
    }

    var kind: Kind
    var settlement: Settlement
    /// Axis 2: past the due date and not settled.
    var isOverdue = false
    /// Advance requests: a payment tax document exists for the payment.
    var taxDocumentIssued = false
    /// Advance requests: an issued final invoice deducted it.
    var deductedInFinal = false
    /// Tax documents marked "Označit k opravě dobropisem…". Such a document is never overdue.
    var markedForCreditNote = false

    /// The one label to show. The order of the checks is the precedence in design-system.md §4.3.
    var label: DocumentStateLabel {
        if settlement == .draft { return .draft }
        if markedForCreditNote { return .markedForCreditNote }
        if settlement == .closedUnpaid { return .closedUnpaid }
        if kind == .advanceRequest && deductedInFinal { return .settledInFinal }
        // A payment tax document records money already received, so it is paid by definition.
        if kind == .paymentTaxDocument { return .issuedPaid }
        if isOverdue && (settlement == .open || settlement == .partlyPaid) { return .overdue }

        switch (kind, settlement) {
        case (.advanceRequest, .open):
            return .awaitingPayment
        case (.advanceRequest, .paid):
            return taxDocumentIssued ? .taxDocumentIssued : .paidTaxDocumentMissing
        case (_, .open):
            return .issued
        case (_, .partlyPaid):
            return .partlyPaid
        case (_, .paid):
            return .paid
        case (_, .overpaid):
            return .overpaid
        case (_, .settledByAdvances):
            return .paidByAdvances
        case (_, .draft), (_, .closedUnpaid):
            // Both are handled above; listed so the switch stays exhaustive.
            return .draft
        }
    }
}

/// One label per displayable document state. English defaults use sentence case (design-system.md §9).
enum DocumentStateLabel: String, CaseIterable, Sendable {
    case draft, issued, awaitingPayment, partlyPaid, paid, paidTaxDocumentMissing, taxDocumentIssued
    case settledInFinal, closedUnpaid, issuedPaid, paidByAdvances, overpaid, overdue, markedForCreditNote

    var style: StatusStyle {
        switch self {
        case .draft:
            return StatusStyle(
                tone: .neutral, symbol: "pencil.circle",
                label: LocalizedStringResource("status.document.draft", defaultValue: "Draft", table: "DesignSystem"))
        case .issued:
            return StatusStyle(
                tone: .pending, symbol: "clock",
                label: LocalizedStringResource("status.document.issued", defaultValue: "Issued", table: "DesignSystem"))
        case .awaitingPayment:
            return StatusStyle(
                tone: .pending, symbol: "clock",
                label: LocalizedStringResource(
                    "status.document.awaitingPayment", defaultValue: "Awaiting payment", table: "DesignSystem"))
        case .partlyPaid:
            return StatusStyle(
                tone: .caution, symbol: "circle.lefthalf.filled",
                label: LocalizedStringResource(
                    "status.document.partlyPaid", defaultValue: "Partly paid", table: "DesignSystem"))
        case .paid:
            return StatusStyle(
                tone: .success, symbol: "checkmark.circle.fill",
                label: LocalizedStringResource("status.document.paid", defaultValue: "Paid", table: "DesignSystem"))
        case .paidTaxDocumentMissing:
            return StatusStyle(
                tone: .caution, symbol: "checkmark.circle.trianglebadge.exclamationmark",
                label: LocalizedStringResource(
                    "status.document.paidTaxDocumentMissing", defaultValue: "Paid – tax document missing",
                    table: "DesignSystem"))
        case .taxDocumentIssued:
            return StatusStyle(
                tone: .success, symbol: "checkmark.circle.fill",
                label: LocalizedStringResource(
                    "status.document.taxDocumentIssued", defaultValue: "Tax document issued", table: "DesignSystem"))
        case .settledInFinal:
            // The badge detail carries the final invoice number.
            return StatusStyle(
                tone: .neutral, symbol: "checkmark.seal",
                label: LocalizedStringResource(
                    "status.document.settledInFinal", defaultValue: "Settled in final invoice", table: "DesignSystem"))
        case .closedUnpaid:
            return StatusStyle(
                tone: .neutral, symbol: "xmark.circle",
                label: LocalizedStringResource(
                    "status.document.closedUnpaid", defaultValue: "Closed unpaid", table: "DesignSystem"))
        case .issuedPaid:
            return StatusStyle(
                tone: .success, symbol: "checkmark.circle.fill",
                label: LocalizedStringResource(
                    "status.document.issuedPaid", defaultValue: "Issued (paid)", table: "DesignSystem"))
        case .paidByAdvances:
            return StatusStyle(
                tone: .success, symbol: "checkmark.circle.fill",
                label: LocalizedStringResource(
                    "status.document.paidByAdvances", defaultValue: "Paid (by advances)", table: "DesignSystem"))
        case .overpaid:
            return StatusStyle(
                tone: .caution, symbol: "plus.circle.fill",
                label: LocalizedStringResource("status.document.overpaid", defaultValue: "Overpaid", table: "DesignSystem"))
        case .overdue:
            return StatusStyle(
                tone: .danger, symbol: "exclamationmark.circle.fill",
                label: LocalizedStringResource("status.document.overdue", defaultValue: "Overdue", table: "DesignSystem"))
        case .markedForCreditNote:
            // The Czech wording waits for the accountant (design-system.md §9, ACCT).
            return StatusStyle(
                tone: .neutral, symbol: "flag",
                label: LocalizedStringResource(
                    "status.document.markedForCreditNote", defaultValue: "Marked for credit note",
                    table: "DesignSystem"))
        }
    }
}

// MARK: - Bank match state (v0.2)

/// The state of one bank statement line in the matching queue.
enum BankMatchState: String, CaseIterable, Sendable {
    /// The payment is already in the app, recorded by hand before the import.
    case alreadyRecorded
    case matched
    case suggested
    case unmatched
    /// "Not an invoice": a fee, software, rent, tax or owner transfer.
    case ignored

    var style: StatusStyle {
        switch self {
        case .alreadyRecorded:
            return StatusStyle(
                tone: .success, symbol: "checkmark.circle",
                label: LocalizedStringResource(
                    "status.match.alreadyRecorded", defaultValue: "Already recorded", table: "DesignSystem"))
        case .matched:
            return StatusStyle(
                tone: .success, symbol: "checkmark.circle.fill",
                label: LocalizedStringResource("status.match.matched", defaultValue: "Matched", table: "DesignSystem"))
        case .suggested:
            return StatusStyle(
                tone: .caution, symbol: "checkmark.circle.badge.questionmark",
                label: LocalizedStringResource("status.match.suggested", defaultValue: "Suggested", table: "DesignSystem"))
        case .unmatched:
            return StatusStyle(
                tone: .pending, symbol: "circle.dashed",
                label: LocalizedStringResource("status.match.unmatched", defaultValue: "Unmatched", table: "DesignSystem"))
        case .ignored:
            return StatusStyle(
                tone: .neutral, symbol: "minus.circle",
                label: LocalizedStringResource("status.match.ignored", defaultValue: "Not an invoice", table: "DesignSystem"))
        }
    }
}
