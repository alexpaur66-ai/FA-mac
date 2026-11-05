import Foundation
import GRDB
import InvoicingCore

/// A payment received on an advance request for § 64 goods that a final invoice can list as paid in advance
/// (ADR 0012).
public struct PaidAdvanceCandidate: Hashable, Sendable, Identifiable {
    public let payment: DocumentPayment
    public let advanceRequestID: String
    public let advanceNumber: String
    /// What a final invoice can still list for the payment: its amount, or less when refunds or credit moved
    /// away from the advance left less on it.
    public let available: Money
    /// `PaidAdvance.treatment(of:)` of the advance's lines.
    public let advanceTreatment: VATTreatment?

    public var id: String { payment.id }

    /// The row a final invoice lists for the payment.
    public var paidAdvance: PaidAdvance {
        PaidAdvance(advanceNumber: advanceNumber, paidOn: payment.paidOn, amount: available.amount, currency: available.currency,
                    paymentID: payment.id, advanceTreatment: advanceTreatment)
    }
}

// Advances paid on § 64 goods, settled on a final invoice as paid in advance (ADR 0012).
extension DocumentStore {
    /// Payments a final invoice of the customer (`customerID`) in `currency` can list as paid in advance: money
    /// received on the customer's issued advance requests whose lines are all § 64 goods, without an issued
    /// payment tax document and settled by no final invoice, oldest advance first (see `candidates`).
    public func paidAdvanceCandidates(customerID: String, currency: Currency) throws -> [PaidAdvanceCandidate] {
        try database.queue.read { db in
            let advances = try DocumentRecord
                .filter(Column("kind") == DocumentKind.advanceRequest.rawValue && Column("status") == DocumentStatus.issued.rawValue)
                .filter(Column("customerID") == customerID && Column("currency") == currency.code)
                .order(Column("issueDate"), Column("number"))
                .fetchAll(db)
            return try advances.flatMap { try Self.candidates(db, advance: $0) }
        }
    }

    /// The same for one advance request: what Create Final Invoice lists as paid in advance. Empty for any
    /// other document, and for an advance whose lines are not all § 64 goods.
    public func paidAdvanceCandidates(ofAdvanceRequest id: String) throws -> [PaidAdvanceCandidate] {
        try database.queue.read { db in
            guard let advance = try DocumentRecord.fetchOne(db, key: id),
                  advance.kind == DocumentKind.advanceRequest.rawValue, advance.status == DocumentStatus.issued.rawValue else { return [] }
            return try Self.candidates(db, advance: advance)
        }
    }

    /// The payments of one issued advance request that a final invoice can still list as paid in advance:
    /// received (or credited) without an issued payment tax document and settled by no final invoice, oldest
    /// first, when all of the advance's lines are § 64 goods. Each is offered for at most what the advance
    /// still holds (payments net of refunds and credit moved away, less what final invoices settled), so a
    /// refund is never listed as paid; a payment with nothing left is left out.
    static func candidates(_ db: Database, advance: DocumentRecord) throws -> [PaidAdvanceCandidate] {
        guard let number = advance.number, try advance.isIntraCommunityGoodsOnly() else { return [] }
        let currency = Currency(code: advance.currency)
        let held = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM documentPayment WHERE documentID = ?",
                                      arguments: [advance.id]) ?? 0
        let settled = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM paidAdvance WHERE advanceRequestID = ?",
                                         arguments: [advance.id]) ?? 0
        var left = held - settled
        var result: [PaidAdvanceCandidate] = []
        let payments = try DocumentPaymentRecord.filter(Column("documentID") == advance.id)
            .order(Column("paidOn"), Column("createdAt")).fetchAll(db)
        for payment in payments where left > 0 && payment.paymentKind?.isIncoming == true {
            if try Self.receiptIsIssued(db, payment) { continue }
            if try PaidAdvanceRecord.filter(Column("paymentID") == payment.id).fetchCount(db) > 0 { continue }
            let units = min(payment.amount, left)
            left -= units
            result.append(PaidAdvanceCandidate(
                payment: try payment.payment(receiptIssued: false), advanceRequestID: advance.id, advanceNumber: number,
                available: MinorUnits.money(units, currency), advanceTreatment: .intraCommunityGoods))
        }
        return result
    }

    /// Records which payments the final invoice settled as paid in advance. An advance number that is not in
    /// the database (an advance from before the app) is allowed without a payment and returned, so the audit
    /// event can name it. Every other row must name its stored payment (`PaidAdvance.paymentID`): money
    /// received on the issued advance request of that number, for the final invoice's customer and in its
    /// currency, on the row's day and for at least the row's amount, without an issued payment tax document
    /// (such an advance is deducted, § 37a ZDPH) and settled by no other final invoice (`advanceAlreadySettled`).
    /// What the final invoices settle on an advance request may not exceed its payments net of refunds
    /// (`paidAdvancesExceedPaid`). Throws `paidAdvanceInvalid` for anything else; other kinds return no links.
    static func linkPaidAdvances(_ db: Database, finalInvoice: DocumentRecord, document: Document, at stamp: String) throws -> [String] {
        guard document.kind.deductsAdvances else { return [] }
        let currency = Currency(code: finalInvoice.currency)
        var external: [String] = []
        var linkedAdvances: [(id: String, number: String)] = []
        var seenPayments: Set<String> = []
        for paid in document.paidAdvances ?? [] {
            let number = paid.advanceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !number.isEmpty else { continue }
            guard let paymentID = paid.paymentID else {
                // An advance the app does not know; one it knows must name its payment.
                guard try DocumentRecord.filter(Column("number") == number).fetchOne(db) == nil else {
                    throw DataError.paidAdvanceInvalid(number: number, detail: "no payment of the advance is named")
                }
                external.append(number)
                continue
            }
            guard seenPayments.insert(paymentID).inserted else {
                throw DataError.paidAdvanceInvalid(number: number, detail: "the payment \(paymentID) is listed twice")
            }
            guard let payment = try DocumentPaymentRecord.fetchOne(db, key: paymentID) else {
                throw DataError.paidAdvanceInvalid(number: number, detail: "the payment \(paymentID) does not exist")
            }
            guard let advance = try DocumentRecord.fetchOne(db, key: payment.documentID),
                  advance.kind == DocumentKind.advanceRequest.rawValue, advance.status == DocumentStatus.issued.rawValue else {
                throw DataError.paidAdvanceInvalid(number: number, detail: "the payment is not on an issued advance request")
            }
            guard advance.number == number else {
                throw DataError.paidAdvanceInvalid(number: number, detail: "the payment is on \(advance.number ?? advance.id)")
            }
            guard advance.currency == finalInvoice.currency else {
                throw DataError.paidAdvanceInvalid(number: number, detail: "in \(advance.currency), the final invoice is in \(finalInvoice.currency)")
            }
            guard Self.sameCustomer(advance, finalInvoice) else {
                throw DataError.paidAdvanceInvalid(number: number,
                                                   detail: "for \(advance.customerName), the final invoice is for \(finalInvoice.customerName)")
            }
            guard payment.paymentKind?.isIncoming == true else {
                throw DataError.paidAdvanceInvalid(number: number, detail: "a \(payment.kind) payment is not money received")
            }
            guard payment.paidOn == paid.paidOn.isoString else {
                throw DataError.paidAdvanceInvalid(number: number,
                                                   detail: "the payment was received on \(payment.paidOn), not on \(paid.paidOn.isoString)")
            }
            let units = try MinorUnits.of(paid.amount, currency)
            guard units > 0, units <= payment.amount else {
                throw DataError.paidAdvanceInvalid(
                    number: number,
                    detail: "the payment is \(MinorUnits.money(payment.amount, currency)), the final invoice lists \(MinorUnits.money(units, currency))")
            }
            if try Self.receiptIsIssued(db, payment) {
                throw DataError.paidAdvanceInvalid(number: number, detail: "the payment has an issued tax document; deduct that instead")
            }
            if let existing = try PaidAdvanceRecord.filter(Column("paymentID") == paymentID).fetchOne(db) {
                throw DataError.advanceAlreadySettled(advanceNumber: number, by: existing.finalInvoiceNumber)
            }
            try PaidAdvanceRecord(id: UUID().uuidString, finalInvoiceID: finalInvoice.id, finalInvoiceNumber: finalInvoice.number ?? "",
                                  paymentID: paymentID, advanceRequestID: advance.id, advanceNumber: number, amount: units,
                                  currency: finalInvoice.currency, createdAt: stamp).insert(db)
            if !linkedAdvances.contains(where: { $0.id == advance.id }) {
                linkedAdvances.append((id: advance.id, number: number))
            }
        }
        // What the final invoices settle on an advance request stays within what it holds, refunds included.
        for advance in linkedAdvances {
            let held = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM documentPayment WHERE documentID = ?",
                                          arguments: [advance.id]) ?? 0
            let settled = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM paidAdvance WHERE advanceRequestID = ?",
                                             arguments: [advance.id]) ?? 0
            guard settled > held else { continue }
            let listed = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM paidAdvance WHERE advanceRequestID = ? AND finalInvoiceID = ?",
                                            arguments: [advance.id, finalInvoice.id]) ?? 0
            throw DataError.paidAdvancesExceedPaid(advanceNumber: advance.number,
                                                   available: MinorUnits.money(max(held - (settled - listed), 0), currency),
                                                   listed: MinorUnits.money(listed, currency))
        }
        return external
    }

    /// Refuses a payment tax document for a payment an issued final invoice settled as paid in advance: the
    /// final invoice took it without one (`paymentSettled`).
    static func checkNotSettled(_ db: Database, payment: DocumentPaymentRecord) throws {
        if let settled = try PaidAdvanceRecord.filter(Column("paymentID") == payment.id).fetchOne(db) {
            throw DataError.paymentSettled(paymentID: payment.id, finalInvoiceNumber: settled.finalInvoiceNumber)
        }
    }

    /// The payments an issued final invoice settled as paid in advance, by advance number.
    public func paidAdvances(ofFinalInvoice id: String) throws -> [PaidAdvanceLink] {
        try database.queue.read { db in
            try PaidAdvanceRecord.filter(Column("finalInvoiceID") == id).order(Column("advanceNumber"), Column("createdAt"))
                .fetchAll(db).map { $0.link() }
        }
    }

    /// The final invoice that settled a payment as paid in advance, if any.
    public func paidAdvance(ofPayment id: String) throws -> PaidAdvanceLink? {
        try database.queue.read { db in
            try PaidAdvanceRecord.filter(Column("paymentID") == id).fetchOne(db)?.link()
        }
    }

    /// The settled payments of an advance request, by final invoice number.
    public func paidAdvances(ofAdvanceRequest id: String) throws -> [PaidAdvanceLink] {
        try database.queue.read { db in
            try PaidAdvanceRecord.filter(Column("advanceRequestID") == id).order(Column("finalInvoiceNumber"), Column("createdAt"))
                .fetchAll(db).map { $0.link() }
        }
    }
}
