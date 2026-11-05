// The states of every document, kept fresh by a GRDB observation (ADR 0007, ADR 0008). One per window.

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

    private let stores: Stores
    @ObservationIgnored private var task: Task<Void, Never>?

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
        states.filter { filter.matches($0, today: today) }.map { DocumentRow(state: $0) }
    }

    /// Counts for the sidebar badges (Drafts, Overdue, Open advances).
    var badgeCounts: [DocumentSmartFilter: Int] {
        var counts: [DocumentSmartFilter: Int] = [:]
        for filter in DocumentSmartFilter.allCases where filter.showsBadge {
            counts[filter] = states.filter { filter.matches($0, today: today) }.count
        }
        return counts
    }
}
