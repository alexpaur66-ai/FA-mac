// Stock (screens-flows.md §2n, ADR 0013): a rough list for reordering. The model holds the items with their
// figures, runs every change through the store and registers its undo on the window's undo manager. Nothing
// here ever blocks invoicing (rule 2).

import Foundation
import InvoicingCore
import InvoicingData
import Observation

@MainActor @Observable
final class StockModel {
    private(set) var states: [StockItemState] = []
    /// Every item by id, the archived ones too: a draft's line linked to an archived item still takes from
    /// stock and shows its marker (§2n "Edge cases").
    private var allStates: [String: StockItemState] = [:]
    private(set) var error: String?
    /// False until a load succeeded, so a failed first load is not shown as "no stock items yet".
    private(set) var loaded = false
    /// The sheet the Stock section shows; set by the toolbar, the menus, the context menu and ↩.
    var sheet: StockSheet?
    let stores: Stores

    init(stores: Stores) {
        self.stores = stores
        reload()
    }

    var stock: StockStore { StockStore(stores.database) }

    func reload() {
        do {
            let all = try stock.states(includeArchived: true)
            states = all.filter { !$0.item.isArchived }
            allStates = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            error = nil
            loaded = true
        } catch {
            self.error = ErrorText.message(error)
        }
    }

    func state(id: String) -> StockItemState? {
        states.first { $0.id == id }
    }

    /// An item by id whether archived or not: what a linked line takes from.
    func anyState(id: String) -> StockItemState? {
        allStates[id]
    }

    /// A stock item exists, archived or not: the client page shows its Items tab (§2n).
    var hasItems: Bool { !allStates.isEmpty }

    /// The client page's Items tab: what the client bought, from the "out" movements of their issued documents.
    func clientItems(customerID: String, year: Int) -> [ClientStockItem] {
        (try? stock.clientItems(customerID: customerID, year: year)) ?? []
    }

    /// The sidebar badge: the items running low.
    var lowCount: Int { states.filter(\.isLow).count }

    func movements(itemID: String) -> [StockMovement] {
        (try? stock.movements(itemID: itemID)) ?? []
    }

    // MARK: Changes, each undoable (screens-flows.md §2n)

    /// Adds an item; returns it, or throws a `StockError` for the sheet to show at its field.
    func add(name: String, unit: String, reorderLevel: Decimal?, onHand: Decimal?, undoManager: UndoManager?) throws -> StockItem {
        let item = try stock.add(name: name, unit: unit, reorderLevel: reorderLevel, onHand: onHand,
                                 day: CalendarDay(Date(), in: .current))
        reload()
        let itemID = item.id
        // Only what this action recorded: the item and its initial count, if any.
        let initial = Set(movements(itemID: itemID).map(\.sequence))
        register(undoManager, name: L.undoNewStockItem) { model in
            // A movement recorded since (another window) keeps the item and its movements in place.
            let current = Set(model.movements(itemID: itemID).map(\.sequence))
            guard current == initial else { return }
            // The count recorded with it goes first, then the item, which now has no movements.
            for sequence in initial {
                try? model.stock.deleteMovement(sequence: sequence)
            }
            _ = try? model.stock.delete(id: itemID)
        }
        return item
    }

    /// A new name, unit or reorder level from the detail's header.
    func update(_ item: StockItem, undoManager: UndoManager?) throws {
        guard let old = state(id: item.id)?.item, old != item else { return }
        try stock.update(item)
        reload()
        register(undoManager, name: L.undoChangeStockItem) { model in
            try? model.stock.update(old)
        }
    }

    func receive(itemID: String, quantity: Decimal, day: CalendarDay, note: String, undoManager: UndoManager?) throws {
        let sequence = try stock.receive(itemID: itemID, quantity: quantity, day: day, note: note)
        reload()
        registerMovementUndo(undoManager, sequence: sequence, name: L.undoReceive)
    }

    func takeOut(itemID: String, quantity: Decimal, day: CalendarDay, note: String, undoManager: UndoManager?) throws {
        let sequence = try stock.takeOut(itemID: itemID, quantity: quantity, day: day, note: note)
        reload()
        registerMovementUndo(undoManager, sequence: sequence, name: L.undoTakeOut)
    }

    func count(itemID: String, onHand: Decimal, day: CalendarDay, undoManager: UndoManager?) throws {
        let sequence = try stock.count(itemID: itemID, onHand: onHand, day: day, today: CalendarDay(Date(), in: .current))
        reload()
        registerMovementUndo(undoManager, sequence: sequence, name: L.undoCount)
    }

    /// Deletes an item with no movements (Edit ▸ Delete); nil, or why it failed.
    func delete(itemID: String, undoManager: UndoManager?) -> String? {
        do {
            let deleted = try stock.delete(id: itemID)
            reload()
            register(undoManager, name: L.undoDeleteStockItem) { model in
                try? model.stock.restore(deleted.item, links: deleted.links)
            }
            return nil
        } catch {
            return ErrorText.message(error)
        }
    }

    /// Archives an item with movements: it leaves the list; Undo brings it back.
    func archive(itemID: String, undoManager: UndoManager?) -> String? {
        do {
            try stock.setArchived(id: itemID, archived: true)
            reload()
            register(undoManager, name: L.undoArchiveStockItem) { model in
                try? model.stock.setArchived(id: itemID, archived: false)
            }
            return nil
        } catch {
            return ErrorText.message(error)
        }
    }

    private func registerMovementUndo(_ undoManager: UndoManager?, sequence: Int64, name: LocalizedStringResource) {
        register(undoManager, name: name) { model in
            try? model.stock.deleteMovement(sequence: sequence)
        }
    }

    /// Registers `undo` on the window's undo manager; the model reloads after it runs.
    private func register(_ undoManager: UndoManager?, name: LocalizedStringResource,
                          _ undo: @escaping @MainActor @Sendable (StockModel) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                undo(model)
                model.reload()
            }
        }
        undoManager.setActionName(String(localized: name))
    }
}

/// The sheets of the Stock section.
enum StockSheet: Identifiable, Hashable {
    case newItem
    case count(String)
    case receive(String)
    case takeOut(String)

    var id: String {
        switch self {
        case .newItem: "new"
        case .count(let id): "count." + id
        case .receive(let id): "receive." + id
        case .takeOut(let id): "takeOut." + id
        }
    }
}

/// Quantities as design-system §9 writes them: up to three decimals, the locale's separators, a real minus.
enum StockFormat {
    static func number(_ value: Decimal, locale: Locale) -> String {
        let text = value.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(0...3)))
        return text.hasPrefix("-") ? "−" + String(text.dropFirst()) : text
    }

    /// "120 ks"; without a unit just the number.
    static func quantity(_ value: Decimal, unit: String, locale: Locale) -> String {
        let figure = number(value, locale: locale)
        return unit.isEmpty ? figure : figure + " " + unit
    }

    /// "+50" or "−25": a history line's change.
    static func change(_ value: Decimal, sign: Int, locale: Locale) -> String {
        (sign < 0 ? "−" : "+") + number(value, locale: locale)
    }
}
