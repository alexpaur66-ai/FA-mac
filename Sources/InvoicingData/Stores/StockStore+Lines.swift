import Foundation
import GRDB
import InvoicingCore

/// One item on the Issue sheet's stock row: its lines' quantities added up, and on hand after Issue.
public struct StockIssueRow: Hashable, Sendable, Identifiable {
    public let itemID: String
    public let name: String
    public let unit: String
    public let quantity: Decimal
    public let leftAfter: Decimal
    /// The DUZP is on or before the item's latest count: the count already saw the goods gone, so on hand
    /// doesn't change (screens-flows.md §2n, edge cases).
    public let countedAfterTaxPoint: Bool

    public var id: String { itemID }
}

/// The links of document lines to stock items (screens-flows.md §2c "Stock in the lines", §2n, ADR 0013 rule 4).
/// They live beside the document: its snapshot, hash and PDF never mention stock.
extension StockStore {
    /// Only an Invoice or a Final invoice takes goods out, at Issue (§2n rule 5).
    public static func takesGoodsOut(_ kind: DocumentKind) -> Bool {
        kind == .invoice || kind == .finalInvoice
    }

    /// Line id → item id for a document's linked lines.
    public func links(documentID: String) throws -> [String: String] {
        try database.queue.read { db in
            Dictionary(try Self.linkRows(db, documentID: documentID).map { ($0.lineID, $0.itemID) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// The document's links as rows, for an Undo that brings a deleted draft back.
    public func linkRows(documentID: String) throws -> [StockLineLink] {
        try database.queue.read { db in try Self.linkRows(db, documentID: documentID) }
    }

    /// Links a saved document's line to an item, replacing any link the line had.
    public func link(documentID: String, lineID: String, itemID: String) throws {
        try database.queue.write { db in
            guard try Self.item(db, id: itemID) != nil else { throw StockError.itemNotFound(itemID) }
            try db.execute(sql: "INSERT OR REPLACE INTO documentLineStock (documentID, lineID, itemID) VALUES (?, ?, ?)",
                           arguments: [documentID, lineID, itemID])
        }
    }

    /// Don't Take from Stock: the line keeps its text and takes nothing.
    public func unlink(documentID: String, lineID: String) throws {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM documentLineStock WHERE documentID = ? AND lineID = ?", arguments: [documentID, lineID])
        }
    }

    /// Duplicate as Draft and Create Final Invoice copy the lines with their links; `lineIDs` maps each source
    /// line to its copy.
    public func copyLinks(from sourceID: String, to targetID: String, lineIDs: [String: String]) throws {
        try database.queue.write { db in
            for link in try Self.linkRows(db, documentID: sourceID) {
                guard let copy = lineIDs[link.lineID] else { continue }
                try db.execute(sql: "INSERT OR REPLACE INTO documentLineStock (documentID, lineID, itemID) VALUES (?, ?, ?)",
                               arguments: [targetID, copy, link.itemID])
            }
        }
    }

    /// Undo of Delete Draft: the links whose document and item still exist come back.
    public func restoreLinks(_ links: [StockLineLink]) throws {
        try database.queue.write { db in
            for link in links {
                guard try Self.documentExists(db, link.documentID), try Self.item(db, id: link.itemID) != nil else { continue }
                try db.execute(sql: "INSERT OR REPLACE INTO documentLineStock (documentID, lineID, itemID) VALUES (?, ?, ?)",
                               arguments: [link.documentID, link.lineID, link.itemID])
            }
        }
    }

    /// The unit price of the last issued line for the item in this currency (by issue date, then the time of
    /// Issue); nil when there is none. An item has no stored price (§2n rule 6).
    public func lastUnitPrice(itemID: String, currency: Currency) throws -> Decimal? {
        try database.queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT l.documentID, l.lineID FROM documentLineStock l JOIN document d ON d.id = l.documentID
                WHERE l.itemID = ? AND d.status = ? AND d.currency = ?
                ORDER BY d.issueDate DESC, d.issuedAt DESC
                """, arguments: [itemID, DocumentStatus.issued.rawValue, currency.code])
            for row in rows {
                let documentID: String = row["documentID"]
                let lineID: String = row["lineID"]
                guard let document = try DocumentRecord.fetchOne(db, key: documentID)?.decode(),
                      let line = document.lines.first(where: { $0.id == lineID }) else { continue }
                return line.unitPrice
            }
            return nil
        }
    }

    /// What Issue would take out: each linked item once, in line order, with its lines' quantities added up
    /// and on hand after Issue. Empty for a document that takes nothing (§2n rule 5).
    public func issuePreview(documentID: String, kind: DocumentKind, lines: [DocumentLine], taxPoint: CalendarDay) throws -> [StockIssueRow] {
        guard Self.takesGoodsOut(kind) else { return [] }
        return try database.queue.read { db in
            let links = Dictionary(try Self.linkRows(db, documentID: documentID).map { ($0.lineID, $0.itemID) },
                                   uniquingKeysWith: { first, _ in first })
            var order: [String] = []
            var quantities: [String: Decimal] = [:]
            for line in lines where line.quantity > 0 {
                guard let itemID = links[line.id] else { continue }
                if quantities[itemID] == nil { order.append(itemID) }
                quantities[itemID, default: 0] += line.quantity
            }
            return try order.compactMap { itemID -> StockIssueRow? in
                guard let item = try Self.item(db, id: itemID), let quantity = quantities[itemID] else { return nil }
                var facts = try Self.movementFacts(db, itemID: itemID)
                let before = Self.onHand(facts)
                facts.append(MovementFact(itemID: itemID, kind: .takenOut, day: taxPoint, sequence: .max, quantity: quantity,
                                          fromDocument: true))
                let counted = before.lastCounted.map { !($0 < taxPoint) } ?? false
                return StockIssueRow(itemID: itemID, name: item.name, unit: item.unit, quantity: quantity,
                                     leftAfter: Self.onHand(facts).onHand, countedAfterTaxPoint: counted)
            }
        }
    }

    /// At Issue, inside its transaction: links of lines no longer in the document go, and each linked line of an
    /// Invoice or a Final invoice becomes an "out" movement of its quantity, dated the DUZP, with the document
    /// as its source. A line whose unit differs from the item's is taken as typed (no unit conversion).
    static func recordIssue(_ db: Database, document: Document, at stamp: String) throws {
        let present = Set(document.lines.map(\.id))
        let rows = try linkRows(db, documentID: document.id)
        for link in rows where !present.contains(link.lineID) {
            try db.execute(sql: "DELETE FROM documentLineStock WHERE documentID = ? AND lineID = ?",
                           arguments: [document.id, link.lineID])
        }
        guard takesGoodsOut(document.kind) else { return }
        let links = Dictionary(rows.map { ($0.lineID, $0.itemID) }, uniquingKeysWith: { first, _ in first })
        for line in document.lines where line.quantity > 0 {
            guard let itemID = links[line.id] else { continue }
            try insertMovement(db, itemID: itemID, kind: .takenOut, day: document.taxPoint, quantity: line.quantity,
                               previousOnHand: nil, note: nil, documentID: document.id, recordedAt: stamp)
        }
    }

    static func linkRows(_ db: Database, documentID: String) throws -> [StockLineLink] {
        try Row.fetchAll(db, sql: "SELECT * FROM documentLineStock WHERE documentID = ?", arguments: [documentID]).map {
            StockLineLink(documentID: $0["documentID"], lineID: $0["lineID"], itemID: $0["itemID"])
        }
    }
}
