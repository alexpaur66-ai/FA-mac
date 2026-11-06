import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct StockLinesTests {
    private let today = Fixtures.day("2026-11-05")

    /// A CZK invoice draft with two lines: 25 ks and 5 ks of the same item, and a third line without a link.
    private func goodsDraft(id: String = "doc-cz") -> Document {
        var draft = Fixtures.czkDraft(id: id)
        draft.lines = [
            DocumentLine(id: "a", text: "Bolt M8", quantity: 25, unit: "ks", unitPrice: Fixtures.d("12.50"), treatment: .taxable(.standard)),
            DocumentLine(id: "b", text: "Bolt M8, zinc", quantity: 5, unit: "ks", unitPrice: Fixtures.d("13"), treatment: .taxable(.standard)),
            DocumentLine(id: "c", text: "Delivery", quantity: 1, unit: nil, unitPrice: 100, treatment: .taxable(.standard)),
        ]
        return draft
    }

    @Test func anInvoiceTakesItsLinkedLinesOutAtIssueOnTheDUZP() throws {
        let database = try Fixtures.prepared()
        let stock = StockStore(database)
        let documents = DocumentStore(database)
        let bolt = try stock.add(name: "Bolt M8", unit: "ks", day: Fixtures.day("2026-11-01"), now: Fixtures.now)
        try stock.receive(itemID: bolt.id, quantity: 100, day: Fixtures.day("2026-11-01"), note: nil, now: Fixtures.now)
        let draft = goodsDraft()
        try documents.saveDraft(draft, now: Fixtures.now)
        try stock.link(documentID: draft.id, lineID: "a", itemID: bolt.id)
        try stock.link(documentID: draft.id, lineID: "b", itemID: bolt.id)
        // A link of a line deleted from the draft takes nothing and goes at Issue.
        try stock.link(documentID: draft.id, lineID: "gone", itemID: bolt.id)

        let preview = try stock.issuePreview(documentID: draft.id, kind: draft.kind, lines: draft.lines, taxPoint: draft.taxPoint)
        #expect(preview == [StockIssueRow(itemID: bolt.id, name: "Bolt M8", unit: "ks", quantity: 30, leftAfter: 70,
                                          countedAfterTaxPoint: false)])

        try documents.issue(id: draft.id, seriesID: "fv", now: Fixtures.now)
        let onHand = try stock.state(id: bolt.id)?.onHand
        #expect(onHand == 70)
        let outs = try stock.movements(itemID: bolt.id).filter { $0.kind == .takenOut }
        #expect(outs.count == 2)
        let days = Set(outs.map(\.day))
        #expect(days == [Fixtures.day("2026-11-04")])
        let numbers = Set(outs.compactMap(\.documentNumber))
        #expect(numbers == ["FV-2026-001"])
        let links = try stock.links(documentID: draft.id)
        #expect(links == ["a": bolt.id, "b": bolt.id])
        // The last issued line for the item gives a new line its price, in the draft's currency only.
        let czk = try stock.lastUnitPrice(itemID: bolt.id, currency: .czk)
        #expect(czk == Fixtures.d("12.50") || czk == Fixtures.d("13"))
        let eur = try stock.lastUnitPrice(itemID: bolt.id, currency: .eur)
        #expect(eur == nil)
    }

    @Test func anAdvanceTakesNothingAndItsFinalInvoiceCopiesTheLinks() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let stock = StockStore(database)
        let documents = DocumentStore(database)
        let bolt = try stock.add(name: "Bolt M8", unit: "ks", onHand: 40, day: Fixtures.day("2026-11-01"), now: Fixtures.now)
        var advance = goodsDraft(id: "adv")
        advance.kind = .advanceRequest
        advance.taxPointDate = nil
        try documents.saveDraft(advance, now: Fixtures.now)
        try stock.link(documentID: "adv", lineID: "a", itemID: bolt.id)
        let preview = try stock.issuePreview(documentID: "adv", kind: .advanceRequest, lines: advance.lines, taxPoint: advance.taxPoint)
        #expect(preview.isEmpty)
        try documents.issue(id: "adv", seriesID: "zf", now: Fixtures.now)
        let afterAdvance = try stock.state(id: bolt.id)?.onHand
        #expect(afterAdvance == 40)

        // Create Final Invoice copies the lines under new ids, with their links.
        var final = goodsDraft(id: "final")
        final.kind = .finalInvoice
        final.lines = advance.lines.map { line in
            DocumentLine(text: line.text, quantity: line.quantity, unit: line.unit, unitPrice: line.unitPrice, treatment: line.treatment)
        }
        try documents.saveDraft(final, now: Fixtures.now)
        let map = Dictionary(uniqueKeysWithValues: zip(advance.lines.map(\.id), final.lines.map(\.id)))
        try stock.copyLinks(from: "adv", to: "final", lineIDs: map)
        let finalLinks = try stock.links(documentID: "final")
        let firstLineID = try #require(final.lines.first?.id)
        #expect(finalLinks == [firstLineID: bolt.id])
        try documents.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        let afterFinal = try stock.state(id: bolt.id)?.onHand
        #expect(afterFinal == 15)
    }

    @Test func aDUZPOnOrBeforeTheLatestCountChangesNothing() throws {
        let database = try Fixtures.prepared()
        let stock = StockStore(database)
        let documents = DocumentStore(database)
        let bolt = try stock.add(name: "Bolt M8", unit: "ks", day: today, now: Fixtures.now)
        try stock.count(itemID: bolt.id, onHand: 40, day: Fixtures.day("2026-11-04"), today: today, now: Fixtures.now)
        let draft = goodsDraft()
        try documents.saveDraft(draft, now: Fixtures.now)
        try stock.link(documentID: draft.id, lineID: "a", itemID: bolt.id)
        let preview = try stock.issuePreview(documentID: draft.id, kind: draft.kind, lines: draft.lines, taxPoint: draft.taxPoint)
        #expect(preview.first?.leftAfter == 40)
        #expect(preview.first?.countedAfterTaxPoint == true)
        try documents.issue(id: draft.id, seriesID: "fv", now: Fixtures.now)
        let onHand = try stock.state(id: bolt.id)?.onHand
        #expect(onHand == 40)
    }

    @Test func unlinkAndDeletedDraftLinksComeBack() throws {
        let database = try Fixtures.prepared()
        let stock = StockStore(database)
        let documents = DocumentStore(database)
        let bolt = try stock.add(name: "Bolt M8", unit: "ks", day: today, now: Fixtures.now)
        let draft = goodsDraft()
        try documents.saveDraft(draft, now: Fixtures.now)
        try stock.link(documentID: draft.id, lineID: "a", itemID: bolt.id)
        try stock.link(documentID: draft.id, lineID: "b", itemID: bolt.id)
        try stock.unlink(documentID: draft.id, lineID: "b")
        let saved = try stock.linkRows(documentID: draft.id)
        #expect(saved == [StockLineLink(documentID: draft.id, lineID: "a", itemID: bolt.id)])
        try documents.deleteDraft(id: draft.id, now: Fixtures.now)
        let afterDelete = try stock.links(documentID: draft.id)
        #expect(afterDelete.isEmpty)
        try documents.saveDraft(draft, now: Fixtures.now)
        try stock.restoreLinks(saved)
        let restored = try stock.links(documentID: draft.id)
        #expect(restored == ["a": bolt.id])
    }
    @Test func aClientsItemsComeFromTheOutMovementsOfTheirIssuedDocuments() throws {
        let database = try Fixtures.prepared()
        let stock = StockStore(database)
        let documents = DocumentStore(database)
        let bolt = try stock.add(name: "Bolt M8", unit: "ks", onHand: 100, day: Fixtures.day("2026-11-01"), now: Fixtures.now)
        let draft = goodsDraft()
        try documents.saveDraft(draft, now: Fixtures.now)
        try stock.link(documentID: draft.id, lineID: "a", itemID: bolt.id)
        try stock.link(documentID: draft.id, lineID: "b", itemID: bolt.id)
        // Before Issue nothing was bought.
        let before = try stock.clientItems(customerID: "cust-cz", year: 2026)
        #expect(before.isEmpty)
        try documents.issue(id: draft.id, seriesID: "fv", now: Fixtures.now)

        let items = try stock.clientItems(customerID: "cust-cz", year: 2026)
        #expect(items.count == 1)
        let row = try #require(items.first)
        #expect(row.name == "Bolt M8")
        #expect(row.boughtThisYear == 30)
        #expect(row.boughtInAll == 30)
        #expect(row.lastDay == Fixtures.day("2026-11-04"))
        #expect(row.lastDocumentNumber == "FV-2026-001")
        #expect(row.lastPrice == Money(Fixtures.d("12.50"), .czk))
        let lastYear = try stock.clientItems(customerID: "cust-cz", year: 2025)
        #expect(lastYear.first?.boughtThisYear == 0)
        let other = try stock.clientItems(customerID: "cust-de", year: 2026)
        #expect(other.isEmpty)
    }
}
