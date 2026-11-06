import Foundation
import GRDB
import InvoicingCore

// Row types of the tables in `Schema`. Internal: the stores translate them to and from the InvoicingCore
// values the app works with. Column names are the property names.

struct CompanyProfileRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "companyProfile"
    var id: Int64
    var snapshot: String
    var updatedAt: String

    func decode() throws -> CompanyProfile {
        do { return try JSONCodec.decode(CompanyProfile.self, from: snapshot) } catch {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: String(id), detail: "\(error)")
        }
    }
}

struct CustomerRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "customer"
    var id: String
    var name: String
    var searchKey: String
    var countryCode: String
    var vatIdentifier: String?
    var identificationNumber: String?
    var currency: String
    var snapshot: String
    var createdAt: String
    var updatedAt: String
    var archivedAt: String?

    init(customer: Customer, createdAt: String, updatedAt: String, archivedAt: String?) throws {
        id = customer.id
        name = customer.party.name
        searchKey = Self.searchKey(for: customer.party)
        countryCode = customer.party.address.countryCode
        vatIdentifier = customer.party.vatIdentifier?.value
        identificationNumber = customer.party.identificationNumber?.digits
        currency = customer.currency.code
        snapshot = try JSONCodec.encode(customer)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    /// Lower-case text without diacritics that the search matches against: name, city, DIČ, IČO, e-mail.
    static func searchKey(for party: Party) -> String {
        [party.name, party.address.city, party.vatIdentifier?.value ?? "", party.identificationNumber?.digits ?? "", party.email ?? ""]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    func decode() throws -> Customer {
        do { return try JSONCodec.decode(Customer.self, from: snapshot) } catch {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: id, detail: "\(error)")
        }
    }
}

/// A numbering series as the app sees it: the InvoicingCore series plus its display name and the
/// document kinds it numbers.
public struct StoredNumberSeries: Hashable, Sendable, Identifiable {
    public var name: String
    /// Kinds the series numbers; empty means any kind.
    public var kinds: Set<DocumentKind>
    public var series: DocumentNumberSeries

    public init(name: String, kinds: Set<DocumentKind>, series: DocumentNumberSeries) {
        self.name = name
        self.kinds = kinds
        self.series = series
    }

    public var id: String { series.id }

    public func numbers(_ kind: DocumentKind) -> Bool { kinds.isEmpty || kinds.contains(kind) }
}

struct NumberSeriesRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "numberSeries"
    var id: String
    var name: String
    var kinds: String
    var template: String
    var resetsYearly: Bool
    var year: Int
    var lastCounter: Int
    var lastIssuedYear: Int?
    var variableSymbolPrefix: String?

    init(_ stored: StoredNumberSeries) {
        id = stored.series.id
        name = stored.name
        kinds = stored.kinds.map(\.rawValue).sorted().joined(separator: ",")
        template = stored.series.pattern.template
        resetsYearly = stored.series.resetsYearly
        year = stored.series.year
        lastCounter = stored.series.lastCounter
        lastIssuedYear = stored.series.lastIssuedYear
        variableSymbolPrefix = stored.series.variableSymbolPrefix
    }

    func stored() throws -> StoredNumberSeries {
        do {
            let series = try DocumentNumberSeries(id: id, pattern: DocumentNumberPattern(template: template), resetsYearly: resetsYearly,
                                                  year: year, lastCounter: lastCounter, lastIssuedYear: lastIssuedYear,
                                                  variableSymbolPrefix: variableSymbolPrefix)
            let kinds = Set(self.kinds.split(separator: ",").compactMap { DocumentKind(rawValue: String($0)) })
            return StoredNumberSeries(name: name, kinds: kinds, series: series)
        } catch {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: id, detail: "\(error)")
        }
    }
}

/// What a list of documents shows without decoding every snapshot.
public struct DocumentSummary: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: DocumentKind
    public let status: DocumentStatus
    public let number: String?
    public let customerID: String?
    public let customerName: String
    public let issueDate: CalendarDay
    public let taxPointDate: CalendarDay?
    public let dueDate: CalendarDay
    public let currency: Currency
    /// Nil on a draft whose amounts cannot be computed yet (for example a missing exchange rate).
    public let totalGross: Money?
    public let amountDue: Money?
    /// What a final invoice lists as paid in advance (§ 64 goods, ADR 0012); nil when nothing is.
    public let paidInAdvance: Money?
    public let taxableVATCZK: Money?
    public let variableSymbol: String?
    public let relatedDocumentNumber: String?
    /// ISO 8601 timestamp of the issue, nil on a draft.
    public let issuedAt: String?
    /// ISO 8601 timestamp of the last save: the issue for an issued document, the last edit for a draft.
    public let updatedAt: String
}

struct DocumentRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "document"
    var id: String
    var kind: String
    var status: String
    var number: String?
    var customerID: String?
    var customerName: String
    var issueDate: String
    var taxPointDate: String?
    var dueDate: String
    var currency: String
    var totalBase: Int64?
    var totalVAT: Int64?
    var totalGross: Int64?
    var taxableBase: Int64?
    var taxableVAT: Int64?
    var amountDue: Int64?
    var taxableBaseCZK: Int64?
    var taxableVATCZK: Int64?
    /// Since v3: what a final invoice lists as paid in advance; nil when nothing is.
    var paidInAdvance: Int64?
    /// Since v3: the distinct treatments of the lines (`VATTreatment.groupingKey`) as a JSON array; nil on
    /// rows written before.
    var treatments: String?
    var variableSymbol: String?
    var creditorReference: String?
    var relatedDocumentNumber: String?
    var snapshot: String
    var snapshotSHA256: String?
    var createdAt: String
    var updatedAt: String
    var issuedAt: String?
    /// Since v4: false while a draft's issue date floats to the day of Issue (docs-28).
    var issueDateSetByHand: Bool
    /// Since v4: true when a draft's tax point was picked with "Same as the issue date" off, even on the
    /// issue date's day, so it stays put while the issue date floats (docs-28).
    var taxPointSetByHand: Bool

    /// Builds the row for `document`; `totals` is nil when the amounts cannot be computed (a draft may
    /// be incomplete). The hash is stored for issued documents only.
    init(document: Document, totals: DocumentTotals?, createdAt: String, updatedAt: String, issuedAt: String?,
         issueDateSetByHand: Bool = false, taxPointSetByHand: Bool = false) throws {
        id = document.id
        kind = document.kind.rawValue
        status = document.status.rawValue
        number = document.number
        customerID = document.customerID
        customerName = document.customer.name
        issueDate = document.issueDate.isoString
        taxPointDate = document.taxPointDate?.isoString
        dueDate = document.dueDate.isoString
        currency = document.currency.code
        let scale = document.currency
        totalBase = try MinorUnits.ifPresent(totals?.totalBase, scale)
        totalVAT = try MinorUnits.ifPresent(totals?.totalVAT, scale)
        totalGross = try MinorUnits.ifPresent(totals?.totalGross, scale)
        taxableBase = try MinorUnits.ifPresent(totals?.taxableBase, scale)
        taxableVAT = try MinorUnits.ifPresent(totals?.taxableVAT, scale)
        amountDue = try MinorUnits.ifPresent(totals?.amountDue, scale)
        taxableBaseCZK = try MinorUnits.ifPresent(totals?.taxableBaseCZK, .czk)
        taxableVATCZK = try MinorUnits.ifPresent(totals?.taxableVATCZK, .czk)
        if let paid = totals?.paidInAdvance, paid != 0 {
            paidInAdvance = try MinorUnits.of(paid, scale)
        } else {
            paidInAdvance = nil
        }
        treatments = try JSONCodec.encode(document.treatments.map(\.groupingKey))
        variableSymbol = document.payment?.variableSymbol?.digits
        creditorReference = document.payment?.creditorReference?.value
        relatedDocumentNumber = document.relatedDocumentNumber
        snapshot = try JSONCodec.encode(document)
        snapshotSHA256 = issuedAt == nil ? nil : JSONCodec.sha256(snapshot)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.issuedAt = issuedAt
        self.issueDateSetByHand = issueDateSetByHand
        self.taxPointSetByHand = taxPointSetByHand
    }

    func decode() throws -> Document {
        do { return try JSONCodec.decode(Document.self, from: snapshot) } catch {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: id, detail: "\(error)")
        }
    }

    /// True when the row has lines and all of them are § 64 goods (`Document.isIntraCommunityGoodsOnly`),
    /// read from the `treatments` column, or from the snapshot for a row written before the column existed.
    func isIntraCommunityGoodsOnly() throws -> Bool {
        if let treatments, let keys = try? JSONCodec.decode([String].self, from: treatments) {
            return !keys.isEmpty && keys.allSatisfy { $0 == VATTreatment.intraCommunityGoods.groupingKey }
        }
        return try decode().isIntraCommunityGoodsOnly
    }

    func summary() throws -> DocumentSummary {
        guard let kind = DocumentKind(rawValue: kind), let status = DocumentStatus(rawValue: status) else {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: id, detail: "kind \(self.kind), status \(self.status)")
        }
        let currency = Currency(code: currency)
        return DocumentSummary(
            id: id, kind: kind, status: status, number: number, customerID: customerID, customerName: customerName,
            issueDate: try CalendarDay.stored(issueDate, table: Self.databaseTableName, id: id),
            taxPointDate: try CalendarDay.stored(taxPointDate, table: Self.databaseTableName, id: id),
            dueDate: try CalendarDay.stored(dueDate, table: Self.databaseTableName, id: id),
            currency: currency,
            totalGross: totalGross.map { MinorUnits.money($0, currency) },
            amountDue: amountDue.map { MinorUnits.money($0, currency) },
            paidInAdvance: paidInAdvance.map { MinorUnits.money($0, currency) },
            taxableVATCZK: taxableVATCZK.map { MinorUnits.money($0, .czk) },
            variableSymbol: variableSymbol,
            relatedDocumentNumber: relatedDocumentNumber,
            issuedAt: issuedAt,
            updatedAt: updatedAt
        )
    }
}

/// What a payment row records (ADR 0007). The amount's sign follows the kind: incoming kinds are positive,
/// outgoing kinds negative, so the sum of a document's payments is what it has been paid net.
public enum DocumentPaymentKind: String, Sendable, Codable, CaseIterable {
    /// Money received, by hand or from a bank statement.
    case received
    /// Money returned to the customer (an overpayment paid back), negative.
    case refund
    /// Credit of an overpaid document applied here (`DocumentStore.applyCredit`), positive.
    case creditIn
    /// Credit of this overpaid document moved to another document, negative.
    case creditOut

    public var isIncoming: Bool { self == .received || self == .creditIn }
}

/// A payment received against a document, entered by hand or taken from a bank statement; or a refund or
/// a credit moved between documents (see `kind`).
public struct DocumentPayment: Hashable, Sendable, Identifiable {
    public let id: String
    public let documentID: String
    public let paidOn: CalendarDay
    /// Signed: positive for `received` and `creditIn`, negative for `refund` and `creditOut`.
    public let amount: Money
    public let kind: DocumentPaymentKind
    /// The imported bank statement line the payment was matched from; nil when typed in by the user.
    public let bankTransactionID: String?
    /// The payment tax document issued for this payment (an advance received against an advance
    /// request); nil for payments of ordinary invoices.
    public let receiptDocumentID: String?
    /// True while `receiptDocumentID` points to an issued document: the receipt rests on this payment,
    /// so the payment can be neither changed nor deleted.
    public let receiptIssued: Bool
    /// For `creditIn` and `creditOut`: the other leg of the same applied credit.
    public let relatedPaymentID: String?
    public let note: String?

    public var isFromBankImport: Bool { bankTransactionID != nil }
    public var isIncoming: Bool { kind.isIncoming }
}

struct DocumentPaymentRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "documentPayment"
    var id: String
    var documentID: String
    var paidOn: String
    var amount: Int64
    var currency: String
    var kind: String
    var bankTransactionID: String?
    var receiptDocumentID: String?
    var relatedPaymentID: String?
    var note: String?
    var createdAt: String

    var paymentKind: DocumentPaymentKind? { DocumentPaymentKind(rawValue: kind) }

    func payment(receiptIssued: Bool) throws -> DocumentPayment {
        guard let paymentKind else { throw DataError.corruptRecord(table: Self.databaseTableName, id: id, detail: "kind \(kind)") }
        return DocumentPayment(id: id, documentID: documentID,
                               paidOn: try CalendarDay.stored(paidOn, table: Self.databaseTableName, id: id),
                               amount: MinorUnits.money(amount, Currency(code: currency)), kind: paymentKind,
                               bankTransactionID: bankTransactionID, receiptDocumentID: receiptDocumentID,
                               receiptIssued: receiptIssued, relatedPaymentID: relatedPaymentID, note: note)
    }
}

/// Which payment tax document an issued final invoice deducted, and the advance request it belongs to.
public struct AdvanceDeductionLink: Hashable, Sendable, Identifiable {
    public let id: String
    public let finalInvoiceID: String
    public let finalInvoiceNumber: String
    public let receiptDocumentID: String
    public let receiptNumber: String
    /// The advance request the receipt's payment was received on; nil when the receipt has no payment.
    public let advanceRequestID: String?
    /// ISO 8601 UTC, the issue of the final invoice.
    public let createdAt: String
}

struct AdvanceDeductionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "advanceDeduction"
    var id: String
    var finalInvoiceID: String
    var finalInvoiceNumber: String
    var receiptDocumentID: String
    var receiptNumber: String
    var advanceRequestID: String?
    var createdAt: String

    func link() -> AdvanceDeductionLink {
        AdvanceDeductionLink(id: id, finalInvoiceID: finalInvoiceID, finalInvoiceNumber: finalInvoiceNumber,
                             receiptDocumentID: receiptDocumentID, receiptNumber: receiptNumber,
                             advanceRequestID: advanceRequestID, createdAt: createdAt)
    }
}

/// A payment on an advance request for § 64 goods that an issued final invoice settled as paid in
/// advance (ADR 0012): such an advance has no payment tax document.
public struct PaidAdvanceLink: Hashable, Sendable, Identifiable {
    public let id: String
    public let finalInvoiceID: String
    public let finalInvoiceNumber: String
    public let paymentID: String
    public let advanceRequestID: String
    public let advanceNumber: String
    /// The part of the payment the final invoice lists.
    public let amount: Money
    /// ISO 8601 UTC, the issue of the final invoice.
    public let createdAt: String
}

struct PaidAdvanceRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "paidAdvance"
    var id: String
    var finalInvoiceID: String
    var finalInvoiceNumber: String
    var paymentID: String
    var advanceRequestID: String
    var advanceNumber: String
    var amount: Int64
    var currency: String
    var createdAt: String

    func link() -> PaidAdvanceLink {
        PaidAdvanceLink(id: id, finalInvoiceID: finalInvoiceID, finalInvoiceNumber: finalInvoiceNumber, paymentID: paymentID,
                        advanceRequestID: advanceRequestID, advanceNumber: advanceNumber,
                        amount: MinorUnits.money(amount, Currency(code: currency)), createdAt: createdAt)
    }
}

/// The two closing events of screens-flows.md §2d.
public enum DocumentClosureKind: String, Sendable, Codable, CaseIterable {
    /// An issued advance request the customer will never pay ("Uzavřít zálohu bez úhrady…").
    case closedUnpaid
    /// An issued tax document to be corrected by a credit note in Phase 2 ("Označit k opravě dobropisem…").
    case markedForCreditNote
}

/// A dated closing event beside an issued document. The document itself stays as issued.
public struct DocumentClosure: Hashable, Sendable {
    public let documentID: String
    public let kind: DocumentClosureKind
    public let reason: String
    /// ISO 8601 UTC.
    public let closedAt: String
}

struct DocumentClosureRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "documentClosure"
    var documentID: String
    var kind: String
    var reason: String
    var closedAt: String

    func closure() throws -> DocumentClosure {
        guard let kind = DocumentClosureKind(rawValue: kind) else {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: documentID, detail: "kind \(self.kind)")
        }
        return DocumentClosure(documentID: documentID, kind: kind, reason: reason, closedAt: closedAt)
    }
}

struct ExchangeRateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "exchangeRate"
    var currency: String
    var validFor: String
    var amount: Int
    var czkPerAmount: String
    var sourceKind: String
    var sourceOrder: Int?
    var importedAt: String

    init(_ rate: ExchangeRate, importedAt: String) {
        currency = rate.currency.code
        validFor = rate.validFor.isoString
        amount = rate.amount
        czkPerAmount = "\(rate.czkPerAmount)"
        switch rate.source {
        case .cnb(let order):
            sourceKind = "cnb"
            sourceOrder = order
        case .ecb:
            sourceKind = "ecb"
            sourceOrder = nil
        case .manual:
            sourceKind = "manual"
            sourceOrder = nil
        case .fixedAccounting:
            sourceKind = "fixedAccounting"
            sourceOrder = nil
        }
        self.importedAt = importedAt
    }

    func rate() throws -> ExchangeRate {
        let id = "\(currency) \(validFor)"
        guard amount > 0, let value = Decimal(string: czkPerAmount, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: id, detail: "amount \(amount), rate \(czkPerAmount)")
        }
        let source: ExchangeRateSource
        switch sourceKind {
        case "cnb": source = .cnb(order: sourceOrder)
        case "ecb": source = .ecb
        case "manual": source = .manual
        case "fixedAccounting": source = .fixedAccounting
        default: throw DataError.corruptRecord(table: Self.databaseTableName, id: id, detail: "source \(sourceKind)")
        }
        return ExchangeRate(currency: Currency(code: currency), amount: amount, czkPerAmount: value,
                            validFor: try CalendarDay.stored(validFor, table: Self.databaseTableName, id: id), source: source)
    }
}

/// The file format a statement was imported from.
public enum BankStatementFormat: String, Sendable, Codable, CaseIterable {
    /// The Czech ABO/GPC fixed-width format most banks export.
    case gpc
    /// ISO 20022 camt.053.
    case camt053
    case csv
    /// Entered by hand (for example from a PDF statement).
    case manual
}

public enum TransactionMatchState: String, Sendable, Codable, CaseIterable {
    case unmatched
    /// Matched by the variable symbol or payment reference.
    case automatic
    /// Matched or confirmed by the user.
    case manual
    /// Not a payment for a document (fees, transfers between own accounts).
    case ignored
}

/// One imported bank statement; its transactions are separate records.
public struct BankStatement: Hashable, Sendable, Identifiable {
    public var id: String
    public var iban: IBAN
    public var currency: Currency
    public var format: BankStatementFormat
    public var periodFrom: CalendarDay?
    public var periodTo: CalendarDay?
    public var statementNumber: String?
    public var openingBalance: Money?
    public var closingBalance: Money?
    public var fileName: String?
    /// Lower-case hex SHA-256 of the imported file; importing the same file twice is refused.
    public var fileSHA256: String?

    public init(id: String = UUID().uuidString, iban: IBAN, currency: Currency, format: BankStatementFormat,
                periodFrom: CalendarDay? = nil, periodTo: CalendarDay? = nil, statementNumber: String? = nil,
                openingBalance: Money? = nil, closingBalance: Money? = nil, fileName: String? = nil, fileSHA256: String? = nil) {
        self.id = id
        self.iban = iban
        self.currency = currency
        self.format = format
        self.periodFrom = periodFrom
        self.periodTo = periodTo
        self.statementNumber = statementNumber
        self.openingBalance = openingBalance
        self.closingBalance = closingBalance
        self.fileName = fileName
        self.fileSHA256 = fileSHA256
    }
}

/// One line of a bank statement. Incoming payments are positive, outgoing negative.
public struct BankTransaction: Hashable, Sendable, Identifiable {
    public var id: String
    public var statementID: String
    public var bookedOn: CalendarDay
    public var valueOn: CalendarDay?
    public var amount: Money
    public var counterpartyAccount: String?
    public var counterpartyName: String?
    public var variableSymbol: String?
    public var specificSymbol: String?
    public var constantSymbol: String?
    public var creditorReference: String?
    public var message: String?
    /// The bank's own id of the transaction; a second line with the same id in one statement is refused.
    public var bankReference: String?
    public var matchedDocumentID: String?
    public var matchState: TransactionMatchState

    public init(id: String = UUID().uuidString, statementID: String, bookedOn: CalendarDay, valueOn: CalendarDay? = nil, amount: Money,
                counterpartyAccount: String? = nil, counterpartyName: String? = nil, variableSymbol: String? = nil,
                specificSymbol: String? = nil, constantSymbol: String? = nil, creditorReference: String? = nil, message: String? = nil,
                bankReference: String? = nil, matchedDocumentID: String? = nil, matchState: TransactionMatchState = .unmatched) {
        self.id = id
        self.statementID = statementID
        self.bookedOn = bookedOn
        self.valueOn = valueOn
        self.amount = amount
        self.counterpartyAccount = counterpartyAccount
        self.counterpartyName = counterpartyName
        self.variableSymbol = variableSymbol
        self.specificSymbol = specificSymbol
        self.constantSymbol = constantSymbol
        self.creditorReference = creditorReference
        self.message = message
        self.bankReference = bankReference
        self.matchedDocumentID = matchedDocumentID
        self.matchState = matchState
    }
}

struct BankStatementRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "bankStatement"
    var id: String
    var iban: String
    var currency: String
    var format: String
    var periodFrom: String?
    var periodTo: String?
    var statementNumber: String?
    var openingBalance: Int64?
    var closingBalance: Int64?
    var fileName: String?
    var fileSHA256: String?
    var importedAt: String

    init(_ statement: BankStatement, importedAt: String) throws {
        id = statement.id
        iban = statement.iban.value
        currency = statement.currency.code
        format = statement.format.rawValue
        periodFrom = statement.periodFrom?.isoString
        periodTo = statement.periodTo?.isoString
        statementNumber = statement.statementNumber
        openingBalance = try statement.openingBalance.map { try Self.units($0, statement.currency) }
        closingBalance = try statement.closingBalance.map { try Self.units($0, statement.currency) }
        fileName = statement.fileName
        fileSHA256 = statement.fileSHA256
        self.importedAt = importedAt
    }

    private static func units(_ money: Money, _ currency: Currency) throws -> Int64 {
        guard money.currency == currency else { throw DataError.currencyMismatch(expected: currency, actual: money.currency) }
        return try MinorUnits.of(money.amount, currency)
    }

    func statement() throws -> BankStatement {
        guard let iban = IBAN(iban), let format = BankStatementFormat(rawValue: format) else {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: id, detail: "iban \(iban), format \(format)")
        }
        let currency = Currency(code: currency)
        return BankStatement(id: id, iban: iban, currency: currency, format: format,
                             periodFrom: try CalendarDay.stored(periodFrom, table: Self.databaseTableName, id: id),
                             periodTo: try CalendarDay.stored(periodTo, table: Self.databaseTableName, id: id),
                             statementNumber: statementNumber,
                             openingBalance: openingBalance.map { MinorUnits.money($0, currency) },
                             closingBalance: closingBalance.map { MinorUnits.money($0, currency) },
                             fileName: fileName, fileSHA256: fileSHA256)
    }
}

struct BankTransactionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "bankTransaction"
    var id: String
    var statementID: String
    var bookedOn: String
    var valueOn: String?
    var amount: Int64
    var currency: String
    var counterpartyAccount: String?
    var counterpartyName: String?
    var variableSymbol: String?
    var specificSymbol: String?
    var constantSymbol: String?
    var creditorReference: String?
    var message: String?
    var bankReference: String?
    var matchedDocumentID: String?
    var matchState: String

    init(_ transaction: BankTransaction) throws {
        id = transaction.id
        statementID = transaction.statementID
        bookedOn = transaction.bookedOn.isoString
        valueOn = transaction.valueOn?.isoString
        amount = try MinorUnits.of(transaction.amount.amount, transaction.amount.currency)
        currency = transaction.amount.currency.code
        counterpartyAccount = transaction.counterpartyAccount
        counterpartyName = transaction.counterpartyName
        variableSymbol = transaction.variableSymbol
        specificSymbol = transaction.specificSymbol
        constantSymbol = transaction.constantSymbol
        creditorReference = transaction.creditorReference
        message = transaction.message
        bankReference = transaction.bankReference
        matchedDocumentID = transaction.matchedDocumentID
        matchState = transaction.matchState.rawValue
    }

    func transaction() throws -> BankTransaction {
        guard let state = TransactionMatchState(rawValue: matchState) else {
            throw DataError.corruptRecord(table: Self.databaseTableName, id: id, detail: "matchState \(matchState)")
        }
        return BankTransaction(id: id, statementID: statementID,
                               bookedOn: try CalendarDay.stored(bookedOn, table: Self.databaseTableName, id: id),
                               valueOn: try CalendarDay.stored(valueOn, table: Self.databaseTableName, id: id),
                               amount: MinorUnits.money(amount, Currency(code: currency)),
                               counterpartyAccount: counterpartyAccount, counterpartyName: counterpartyName,
                               variableSymbol: variableSymbol, specificSymbol: specificSymbol, constantSymbol: constantSymbol,
                               creditorReference: creditorReference, message: message, bankReference: bankReference,
                               matchedDocumentID: matchedDocumentID, matchState: state)
    }
}

/// One line of the audit trail: who-did-what is "the app", the trail records what and when.
public struct AuditEvent: Hashable, Sendable, Identifiable {
    public let id: Int64
    /// ISO 8601 UTC.
    public let at: String
    public let entity: String
    public let entityID: String
    public let action: String
    public let details: [String: String]?
}

struct AuditEventRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "auditEvent"
    var id: Int64?
    var at: String
    var entity: String
    var entityID: String
    var action: String
    var details: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func event() throws -> AuditEvent {
        guard let id else { throw DataError.corruptRecord(table: Self.databaseTableName, id: "?", detail: "no row id") }
        let details = try self.details.map { try JSONCodec.decode([String: String].self, from: $0) }
        return AuditEvent(id: id, at: at, entity: entity, entityID: entityID, action: action, details: details)
    }
}
