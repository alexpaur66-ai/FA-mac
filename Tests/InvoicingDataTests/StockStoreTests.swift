import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct StockStoreTests {
    private let today = Fixtures.day("2026-11-05")

    private func store() throws -> StockStore {
        StockStore(try Fixtures.prepared())
    }

    @Test func aNewItemWithACountStartsFromIt() throws {
        let stock = try store()
        let item = try stock.add(name: "Bolt M8", unit: "ks", reorderLevel: Fixtures.d("20"), onHand: Fixtures.d("40"), day: today,
                                 now: Fixtures.now)
        let state = try #require(try stock.state(id: item.id))
        #expect(state.onHand == Fixtures.d("40"))
        #expect(state.lastCounted == today)
        #expect(!state.isLow)
        let history = try stock.movements(itemID: item.id)
        #expect(history.count == 1)
        #expect(history.first?.kind == .count)
        #expect(history.first?.previousOnHand == 0)
    }

    @Test func withoutACountOnHandStartsFromZeroAndCanGoBelow() throws {
        let stock = try store()
        let item = try stock.add(name: "Nut M8", unit: "ks", day: today, now: Fixtures.now)
        try stock.receive(itemID: item.id, quantity: Fixtures.d("1.5"), day: today, note: "order 118", now: Fixtures.now)
        try stock.takeOut(itemID: item.id, quantity: Fixtures.d("4"), day: today, note: nil, now: Fixtures.now)
        let state = try #require(try stock.state(id: item.id))
        #expect(state.onHand == Fixtures.d("-2.5"))
        #expect(state.lastCounted == nil)
        #expect(try stock.movements(itemID: item.id).first?.kind == .takenOut)
        #expect(try stock.movements(itemID: item.id).last?.note == "order 118")
    }

    @Test func aCountSetsOnHandAndKeepsWhatTheAppHad() throws {
        let stock = try store()
        let item = try stock.add(name: "Bolt M8", unit: "ks", reorderLevel: Fixtures.d("40"), day: today, now: Fixtures.now)
        try stock.receive(itemID: item.id, quantity: Fixtures.d("46"), day: Fixtures.day("2026-11-01"), note: nil, now: Fixtures.now)
        try stock.count(itemID: item.id, onHand: Fixtures.d("40"), day: Fixtures.day("2026-11-03"), today: today, now: Fixtures.now)
        // A movement dated before the count, recorded later, is already in the count.
        try stock.takeOut(itemID: item.id, quantity: Fixtures.d("5"), day: Fixtures.day("2026-11-02"), note: nil, now: Fixtures.now)
        try stock.receive(itemID: item.id, quantity: Fixtures.d("10"), day: Fixtures.day("2026-11-04"), note: nil, now: Fixtures.now)
        let state = try #require(try stock.state(id: item.id))
        #expect(state.onHand == Fixtures.d("50"))
        #expect(state.lastCounted == Fixtures.day("2026-11-03"))
        let count = try #require(try stock.movements(itemID: item.id).first { $0.kind == .count })
        #expect(count.previousOnHand == Fixtures.d("46"))
        // At the reorder level is running low.
        try stock.takeOut(itemID: item.id, quantity: Fixtures.d("10"), day: today, note: nil, now: Fixtures.now)
        #expect(try stock.state(id: item.id)?.isLow == true)
    }

    @Test func anInvoiceOutOnTheCountDayIsAlreadyCounted() {
        let day = Fixtures.day("2026-11-03")
        let facts = [
            StockStore.MovementFact(itemID: "i", kind: .count, day: day, sequence: 1, quantity: Fixtures.d("40"), fromDocument: false),
            StockStore.MovementFact(itemID: "i", kind: .takenOut, day: day, sequence: 2, quantity: Fixtures.d("25"), fromDocument: true),
            StockStore.MovementFact(itemID: "i", kind: .takenOut, day: day, sequence: 3, quantity: Fixtures.d("2"), fromDocument: false),
        ]
        #expect(StockStore.onHand(facts).onHand == Fixtures.d("38"))
    }

    @Test func quantitiesAndDaysAreChecked() throws {
        let stock = try store()
        let item = try stock.add(name: "Bolt M8", unit: "ks", day: today, now: Fixtures.now)
        #expect(throws: StockError.quantityNotPositive) {
            try stock.receive(itemID: item.id, quantity: 0, day: today, note: nil, now: Fixtures.now)
        }
        #expect(throws: StockError.quantityNotPositive) {
            try stock.takeOut(itemID: item.id, quantity: Fixtures.d("-1"), day: today, note: nil, now: Fixtures.now)
        }
        #expect(throws: StockError.quantityNegative) {
            try stock.count(itemID: item.id, onHand: Fixtures.d("-1"), day: today, today: today, now: Fixtures.now)
        }
        #expect(throws: StockError.dayInFuture) {
            try stock.count(itemID: item.id, onHand: 1, day: today.adding(days: 1), today: today, now: Fixtures.now)
        }
        // A count of 0 is fine.
        try stock.count(itemID: item.id, onHand: 0, day: today, today: today, now: Fixtures.now)
    }

    @Test func namesAreRequiredAndUniqueIgnoringCase() throws {
        let stock = try store()
        let bolt = try stock.add(name: "Bolt M8", unit: "ks", day: today, now: Fixtures.now)
        #expect(throws: StockError.nameRequired) { try stock.add(name: "  ", unit: "ks", day: today, now: Fixtures.now) }
        #expect(throws: StockError.nameTaken("bolt m8")) { try stock.add(name: "bolt m8", unit: "ks", day: today, now: Fixtures.now) }
        var renamed = bolt
        renamed.name = "Bolt M10"
        renamed.reorderLevel = Fixtures.d("5")
        try stock.update(renamed, now: Fixtures.now)
        #expect(try stock.state(id: bolt.id)?.item == renamed)
        // An archived item's name is free again.
        try stock.receive(itemID: bolt.id, quantity: 1, day: today, note: nil, now: Fixtures.now)
        try stock.setArchived(id: bolt.id, archived: true, now: Fixtures.now)
        #expect(try stock.states().isEmpty)
        #expect(try stock.states(includeArchived: true).count == 1)
        try stock.add(name: "Bolt M10", unit: "ks", day: today, now: Fixtures.now)
    }

    @Test func onlyAnItemWithoutMovementsIsDeletedAndUndoBringsItBack() throws {
        let database = try Fixtures.prepared()
        let stock = StockStore(database)
        let item = try stock.add(name: "Bolt M8", unit: "ks", day: today, now: Fixtures.now)
        let draft = Fixtures.czkDraft()
        try DocumentStore(database).saveDraft(draft, now: Fixtures.now)
        let lineID = try #require(draft.lines.first?.id)
        try database.queue.write { db in
            try db.execute(sql: "INSERT INTO documentLineStock (documentID, lineID, itemID) VALUES (?, ?, ?)",
                           arguments: ["doc-cz", lineID, item.id])
        }
        let deleted = try stock.delete(id: item.id)
        #expect(deleted.links == [StockLineLink(documentID: "doc-cz", lineID: lineID, itemID: item.id)])
        #expect(try stock.states().isEmpty)
        try stock.restore(deleted.item, links: deleted.links, now: Fixtures.now)
        let items = try stock.states().map { $0.item }
        #expect(items == [item])
        let links = try database.queue.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documentLineStock") ?? 0
        }
        #expect(links == 1)
        let sequence = try stock.receive(itemID: item.id, quantity: 1, day: today, note: nil, now: Fixtures.now)
        #expect(throws: StockError.itemHasMovements(item.id)) { try stock.delete(id: item.id) }
        // Undo of the receive deletes the movement.
        try stock.deleteMovement(sequence: sequence)
        #expect(try stock.state(id: item.id)?.movementCount == 0)
    }
}
