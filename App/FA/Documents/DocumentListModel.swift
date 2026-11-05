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
    /// A payment an Undo recorded again under a new id, by its old id, so a later Undo of its deleted tax
    /// document relinks the draft to the payment as it is now.
    @ObservationIgnored private var restoredPaymentIDs: [String: String] = [:]

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

    func rows(for filter: DocumentSmartFilter) -> [DocumentRow] {
        states.filter { filter.matches($0, today: today) }.map { DocumentRow(state: $0, today: today) }
    }

    /// Counts for the sidebar badges (Drafts, Overdue, Open advances).
    var badgeCounts: [DocumentSmartFilter: Int] {
        var counts: [DocumentSmartFilter: Int] = [:]
        for filter in DocumentSmartFilter.allCases where filter.showsBadge {
            counts[filter] = states.filter { filter.matches($0, today: today) }.count
        }
        return counts
    }

    // MARK: Undo

    /// A deleted draft with the payment it was the tax document of (as it was at the deletion), so Undo
    /// can relink it.
    struct DeletedDraft: Sendable {
        let document: Document
        let receiptOf: DocumentPayment?
    }

    /// A new ticket for one undo registration of the window, kept alive here (the UndoManager does not
    /// keep its targets alive).
    func makeUndoTicket() -> UndoTicket {
        let ticket = UndoTicket()
        undoTickets.append(ticket)
        return ticket
    }

    /// True the first time a ticket is used: the result line's Undo and Edit ▸ Undo share one ticket.
    private func spend(_ ticket: UndoTicket) -> Bool {
        guard !ticket.spent else { return false }
        ticket.spent = true
        return true
    }

    /// Undo of Delete Draft: writes the drafts back under their ids (`saveDraft` inserts a missing id) and
    /// relinks a payment tax document to its payment, as the payment is now: recorded again by an Undo
    /// under a new id, or gone. A payment that has another tax document by now keeps it; the draft comes
    /// back unlinked and the line says so. The last one restored is selected again.
    func restoreDrafts(_ deleted: [DeletedDraft], ticket: UndoTicket) {
        guard spend(ticket) else { return }
        var lastID: String?
        var unlinked = false
        do {
            for entry in deleted {
                let payment: DocumentPayment? = try entry.receiptOf.flatMap { try currentPayment($0) }
                try stores.documents.saveDraft(entry.document)
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

    /// Undo of Delete Payment: records the payment again (a new row; the amount, day, note and bank line
    /// are the same) and relinks the draft tax document that "Delete Payment Only" kept. Credit legs are
    /// not restored, they are two rows on two documents.
    func restorePayment(_ payment: DocumentPayment, ticket: UndoTicket) {
        guard spend(ticket) else { return }
        var note: String?
        do {
            switch payment.kind {
            case .received:
                let restored = try stores.documents.recordPayment(
                    documentID: payment.documentID, on: payment.paidOn, amount: payment.amount,
                    bankTransactionID: payment.bankTransactionID, note: payment.note)
                restoredPaymentIDs[payment.id] = restored.id
                if let receiptID = payment.receiptDocumentID, !relinkReceipt(receiptID, to: restored) {
                    note = String(localized: L.paymentRestoredUnlinked)
                }
            case .refund:
                let restored = try stores.documents.recordRefund(
                    documentID: payment.documentID, on: payment.paidOn, amount: -payment.amount,
                    bankTransactionID: payment.bankTransactionID, note: payment.note)
                restoredPaymentIDs[payment.id] = restored.id
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

    /// The payment `original` is now: itself, or the row an Undo of its deletion recorded again; nil when
    /// it no longer exists.
    private func currentPayment(_ original: DocumentPayment) throws -> DocumentPayment? {
        var id = original.id
        var seen: Set<String> = []
        while let next = restoredPaymentIDs[id], seen.insert(id).inserted {
            id = next
        }
        return try stores.documents.payments(for: original.documentID).first { $0.id == id }
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
