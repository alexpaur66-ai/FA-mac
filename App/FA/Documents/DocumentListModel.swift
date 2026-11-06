// The states of every document, kept fresh by a GRDB observation (ADR 0007, ADR 0008). One per window.
// It also carries out the window's undo registrations, whose targets are its `UndoTicket`s.

import Foundation
import GRDB
import InvoicingCore
import InvoicingData
import Observation

@MainActor @Observable
final class DocumentListModel {
    private(set) var states: [DocumentState] = []
    /// Set when the observation failed and stopped; the list keeps its last states until `restart()`.
    private(set) var error: String?
    /// The day the states were computed for; the observation restarts when the calendar day changes.
    private(set) var today: CalendarDay
    /// False until the first value arrived, so an empty list is not shown as "no documents" too early.
    private(set) var loaded = false
    /// What the last Undo did: the draft it brought back, why it failed, or what it could not restore. The
    /// window selects the draft again and shows the error or the note.
    private(set) var restoreOutcome: RestoreOutcome?

    struct RestoreOutcome: Equatable {
        /// Changes with every outcome, so two restores of the same draft are two events.
        let token: Int
        let draftID: String?
        let error: String?
        /// Restored, but not everything: a tax document that could not be linked again.
        let note: String?
    }

    private let stores: Stores
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var restoreToken = 0
    /// The tickets of the window's undo registrations; the UndoManager holds its targets unretained.
    @ObservationIgnored private var undoTickets: [UndoTicket] = []
    /// See `searchText(for:)`.
    @ObservationIgnored private var searchCache: [String: SearchEntry] = [:]

    init(stores: Stores) {
        self.stores = stores
        self.today = CalendarDay(Date(), in: .current)
        start()
    }

    deinit {
        task?.cancel()
    }

    /// Restarts the observation for today's date (the main window calls it at midnight, the list's
    /// Try again button after an error).
    func restart() {
        start()
    }

    private func start() {
        task?.cancel()
        let today = CalendarDay(Date(), in: .current)
        self.today = today
        let observation = stores.documents.observeStates(DocumentFilter(), today: today)
        let queue = stores.database.queue
        task = Task { [weak self] in
            do {
                for try await states in observation.values(in: queue) {
                    guard let self, !Task.isCancelled else { return }
                    self.states = states
                    self.loaded = true
                    self.error = nil
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.error = ErrorText.message(error)
                // The list is settled, so an empty list shows the error, not an endless empty table.
                self.loaded = true
            }
        }
    }

    func state(id: String) -> DocumentState? {
        states.first { $0.id == id }
    }

    /// The folded search text a summary does not carry (screens-flows.md §2b): the client's IČO and VAT
    /// ID and the line descriptions, read from the stored document the first time a search needs it. Kept
    /// per save stamp, so a draft edited since is read again; an issued document never changes.
    func searchText(for state: DocumentState) -> String {
        let stamp = state.summary.updatedAt
        if let cached = searchCache[state.id], cached.stamp == stamp { return cached.text }
        var parts: [String] = []
        if let document = try? stores.documents.document(id: state.id) {
            if let number = document.customer.identificationNumber { parts.append(number.description) }
            if let vatID = document.customer.vatIdentifier { parts.append(vatID.description) }
            parts.append(contentsOf: document.lines.map(\.text))
        }
        let text = parts.joined(separator: "\n").folded
        searchCache[state.id] = SearchEntry(stamp: stamp, text: text)
        return text
    }

    private struct SearchEntry {
        let stamp: String
        let text: String
    }

    func rows(for filter: DocumentSmartFilter) -> [DocumentRow] {
        states.filter { filter.matches($0, today: today) }.map { DocumentRow(state: $0, today: today) }
    }

    /// The sidebar badges (screens-flows.md §1.2): the drafts, and the overdue invoices that Unpaid lists.
    var badges: SidebarBadges {
        SidebarBadges(
            drafts: states.filter { $0.summary.status == .draft }.count,
            overdue: overdueCount)
    }

    /// Unpaid's rows that are past their due date: the red badge and the subtitle's "3 overdue".
    var overdueCount: Int {
        states.filter { $0.countsAsUnpaidInvoice && $0.isOverdue }.count
    }

    // MARK: Undo

    /// A deleted draft with the payment it was the tax document of (as it was at the deletion), so Undo
    /// can relink it, and how its dates were set (docs-28), so a date set by hand does not float after Undo.
    struct DeletedDraft: Sendable {
        let document: Document
        let receiptOf: DocumentPayment?
        let dating: DraftDating?
    }

    /// A new ticket for one undo registration of the window, kept alive here (the UndoManager does not
    /// keep its targets alive).
    func makeUndoTicket() -> UndoTicket {
        let ticket = UndoTicket()
        undoTickets.append(ticket)
        return ticket
    }

    /// Before a restore replaces the data: every registration made so far is spent, so neither the line
    /// nor Edit ▸ Undo writes the replaced data into the restored data. The tickets stay alive here, as
    /// the UndoManager may still point at them.
    func invalidateUndo() {
        for ticket in undoTickets {
            ticket.spent = true
        }
    }

    /// True the first time a ticket is used: the result line's Undo and Edit ▸ Undo share one ticket.
    private func spend(_ ticket: UndoTicket) -> Bool {
        guard !ticket.spent else { return false }
        ticket.spent = true
        return true
    }

    /// Undo of Delete Draft: writes the drafts back under their ids (`saveDraft` inserts a missing id) and
    /// relinks a payment tax document to its payment, as the payment is now: still there, recorded again by
    /// an Undo under its id, or gone. A payment that has another tax document by now keeps it; the draft
    /// comes back unlinked and the line says so. The last one restored is selected again.
    func restoreDrafts(_ deleted: [DeletedDraft], ticket: UndoTicket) {
        guard spend(ticket) else { return }
        var lastID: String?
        var unlinked = false
        do {
            for entry in deleted {
                let payment: DocumentPayment? = try entry.receiptOf.flatMap { try currentPayment($0) }
                // The flags are written back as they were; without them, a restored date counts as set by hand.
                try stores.documents.saveDraft(entry.document, issueDateSetByHand: entry.dating?.issueDateSetByHand ?? true,
                                               taxPointSetByHand: entry.dating?.taxPointSetByHand)
                lastID = entry.document.id
                guard entry.receiptOf != nil else { continue }
                guard let payment, payment.receiptDocumentID == nil else {
                    unlinked = true
                    continue
                }
                do {
                    try stores.documents.attachReceipt(paymentID: payment.id, documentID: entry.document.id)
                } catch {
                    unlinked = true
                }
            }
            finishRestore(draftID: lastID, error: nil, note: unlinked ? String(localized: L.draftRestoredUnlinked) : nil)
        } catch {
            finishRestore(draftID: lastID, error: ErrorText.message(error))
        }
    }

    /// Undo of Delete Payment: records the payment again under its id (the amount, day, note and bank line
    /// are the same) and relinks the draft tax document that "Delete Payment Only" kept. Credit legs are
    /// not restored, they are two rows on two documents.
    func restorePayment(_ payment: DocumentPayment, ticket: UndoTicket) {
        guard spend(ticket) else { return }
        var note: String?
        do {
            switch payment.kind {
            case .received:
                let restored = try stores.documents.recordPayment(
                    documentID: payment.documentID, id: payment.id, on: payment.paidOn, amount: payment.amount,
                    bankTransactionID: payment.bankTransactionID, note: payment.note)
                if let receiptID = payment.receiptDocumentID, !relinkReceipt(receiptID, to: restored) {
                    note = String(localized: L.paymentRestoredUnlinked)
                }
            case .refund:
                try stores.documents.recordRefund(
                    documentID: payment.documentID, id: payment.id, on: payment.paidOn, amount: -payment.amount,
                    bankTransactionID: payment.bankTransactionID, note: payment.note)
            case .creditIn, .creditOut:
                break
            }
            finishRestore(draftID: nil, error: nil, note: note)
        } catch {
            finishRestore(draftID: nil, error: ErrorText.message(error))
        }
    }

    /// Links a kept draft tax document back to its restored payment. True when linked, or when the draft
    /// is gone (nothing to link); false when it is still there but can no longer be this payment's
    /// (issued, edited, or the tax document of another payment by now).
    private func relinkReceipt(_ receiptID: String, to payment: DocumentPayment) -> Bool {
        do {
            guard try stores.documents.document(id: receiptID) != nil else { return true }
            try stores.documents.attachReceipt(paymentID: payment.id, documentID: receiptID)
            return true
        } catch {
            return false
        }
    }

    /// The payment `original` is now (an Undo of its deletion records it again under the same id); nil when
    /// it no longer exists.
    private func currentPayment(_ original: DocumentPayment) throws -> DocumentPayment? {
        try stores.documents.payments(for: original.documentID).first { $0.id == original.id }
    }

    private func finishRestore(draftID: String?, error: String?, note: String? = nil) {
        restoreToken += 1
        restoreOutcome = RestoreOutcome(token: restoreToken, draftID: draftID, error: error, note: note)
    }
}

/// One undo registration of the window, and its target: the result line's Undo and Edit ▸ Undo carry out
/// the same registration, so whichever runs first restores and the other does nothing, and the line can
/// take exactly its own registration off the window's stack (`removeAllActions(withTarget:)`).
@MainActor
final class UndoTicket {
    fileprivate(set) var spent = false
}

/// The counts the sidebar shows as badges; zero hides a badge.
struct SidebarBadges: Equatable, Sendable {
    var drafts = 0
    var overdue = 0
}
