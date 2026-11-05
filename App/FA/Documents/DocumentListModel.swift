// The states of every document, kept fresh by a GRDB observation (ADR 0007, ADR 0008). One per window.
// It is also the target of the window's undo registrations (a class the UndoManager can hold weakly).

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
    /// What the last Undo did: the draft it brought back, or why it failed. The window selects the draft
    /// again or shows the error.
    private(set) var restoreOutcome: RestoreOutcome?

    struct RestoreOutcome: Equatable {
        /// Changes with every outcome, so two restores of the same draft are two events.
        let token: Int
        let draftID: String?
        let error: String?
    }

    private let stores: Stores
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var restoreToken = 0

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

    /// A deleted draft with the payment it was the tax document of, so Undo can relink it.
    struct DeletedDraft: Sendable {
        let document: Document
        let receiptOfPaymentID: String?
    }

    /// Undo of Delete Draft: writes the drafts back under their ids (`saveDraft` inserts a missing id) and
    /// relinks a payment tax document to its payment. The last one restored is selected again.
    func restoreDrafts(_ deleted: [DeletedDraft]) {
        var lastID: String?
        do {
            for entry in deleted {
                try stores.documents.saveDraft(entry.document)
                if let paymentID = entry.receiptOfPaymentID {
                    try stores.documents.attachReceipt(paymentID: paymentID, documentID: entry.document.id)
                }
                lastID = entry.document.id
            }
            finishRestore(draftID: lastID, error: nil)
        } catch {
            finishRestore(draftID: lastID, error: ErrorText.message(error))
        }
    }

    /// Undo of Delete Payment: records the payment again (a new row; the amount, day, note and bank line
    /// are the same). Credit legs are not restored, they are two rows on two documents.
    func restorePayment(_ payment: DocumentPayment) {
        do {
            switch payment.kind {
            case .received:
                try stores.documents.recordPayment(documentID: payment.documentID, on: payment.paidOn, amount: payment.amount,
                                                   bankTransactionID: payment.bankTransactionID, note: payment.note)
            case .refund:
                try stores.documents.recordRefund(documentID: payment.documentID, on: payment.paidOn, amount: -payment.amount,
                                                  bankTransactionID: payment.bankTransactionID, note: payment.note)
            case .creditIn, .creditOut:
                break
            }
            finishRestore(draftID: nil, error: nil)
        } catch {
            finishRestore(draftID: nil, error: ErrorText.message(error))
        }
    }

    private func finishRestore(draftID: String?, error: String?) {
        restoreToken += 1
        restoreOutcome = RestoreOutcome(token: restoreToken, draftID: draftID, error: error)
    }
}
