import Foundation
import InvoicingCore

/// The words of the export that the app shows in its own UI (screens-flows.md §2h; design-system.md §9: one
/// term, one meaning in the UI, the PDF and the CSV): the app passes its String Catalog texts, so the CSV says
/// what the badges say. The defaults are the English UI words, for tests.
public struct AccountantExportLabels {
    public var status: (DocumentState) -> String
    public var paymentKind: (DocumentPaymentKind) -> String
    public var paymentSource: (DocumentPayment) -> String
    public var closure: (DocumentClosureKind) -> String
    public var rateSource: (ExchangeRateSource) -> String

    public init(status: @escaping (DocumentState) -> String, paymentKind: @escaping (DocumentPaymentKind) -> String,
                paymentSource: @escaping (DocumentPayment) -> String, closure: @escaping (DocumentClosureKind) -> String,
                rateSource: @escaping (ExchangeRateSource) -> String) {
        self.status = status
        self.paymentKind = paymentKind
        self.paymentSource = paymentSource
        self.closure = closure
        self.rateSource = rateSource
    }

    public static var english: AccountantExportLabels {
        AccountantExportLabels(
            status: { state in
                switch state.settlement {
                case .draft: "Draft"
                case .open: state.isOverdue ? "Overdue" : "Awaiting payment"
                case .partlyPaid: state.isOverdue ? "Overdue" : "Partly paid"
                case .paid, .settledByAdvances: "Paid"
                case .overpaid: "Overpaid"
                case .closedUnpaid: "Closed unpaid"
                }
            },
            paymentKind: { kind in
                switch kind {
                case .received: "Received"
                case .refund: "Refund"
                case .creditIn: "Credit applied"
                case .creditOut: "Credit moved out"
                }
            },
            paymentSource: { payment in
                if payment.isFromBankImport { return "Statement" }
                if payment.kind == .creditIn || payment.kind == .creditOut { return "Credit" }
                return "Typed"
            },
            closure: { kind in
                switch kind {
                case .closedUnpaid: "Closed unpaid"
                case .markedForCreditNote: "Marked for credit note"
                }
            },
            rateSource: { source in
                switch source {
                case .cnb: "ČNB"
                case .ecb: "ECB"
                case .manual: "Typed"
                case .fixedAccounting: "Fixed accounting rate"
                }
            })
    }
}

/// The two CSV files of Export for Accountant (screens-flows.md §2h): a fixed set of columns, so the count
/// never varies, in one fixed format built without the UI locale (design-system.md §9). The format below is
/// the app's choice until the accountant agrees one (ACCT): semicolons, a decimal comma, day.month.year
/// dates, UTF-8 with a byte order mark and CRLF line ends, which is what Czech Excel opens without an import
/// dialog. Change it here only.
public enum AccountantCSV {
    static let delimiter = ";"
    static let lineEnd = "\r\n"
    static let yes = "ano"
    static let no = "ne"

    /// "FA 2026-10": the folder the save panel proposes.
    public static func folderName(_ month: CalendarDay) -> String { "FA " + ExportStore.key(month) }
    public static func documentsFileName(_ month: CalendarDay) -> String { "Documents " + ExportStore.key(month) + ".csv" }
    public static func paymentsFileName(_ month: CalendarDay) -> String { "Payments " + ExportStore.key(month) + ".csv" }

    /// The per-rate columns, in the document currency and then in CZK. BaseOutsideEU (services outside the EU,
    /// not subject to Czech VAT) is not in the spec's list; it keeps those bases out of the other columns.
    static let rateColumnNames = ["Base21", "VAT21", "Base12", "VAT12", "Base0", "BaseExempt", "BaseRC", "BaseOutsideEU"]

    public static let documentColumns: [String] = [
        "Number", "Type", "Daňový doklad", "Issue date", "DUZP", "Due date", "Status",
        "Client name", "IČO", "VAT ID", "Country", "VAT treatment",
        "Currency", "Total",
    ] + rateColumnNames + rateColumnNames.map { $0 + "_CZK" } + [
        "Rate", "RateDate", "RateSource", "RateIsFallback",
        "RelatedDocs", "DeductedAdvance", "DeductedVAT_CZK",
        "Paid amount", "Paid date", "Closing event",
    ]

    public static let paymentColumns = [
        "Paid on", "Document", "Document type", "Client name", "Payment", "Amount", "Currency", "Tax document", "Source", "Note",
    ]

    /// The Documents CSV: a header, then one row per document of the month.
    public static func documents(_ data: AccountantExportData, labels: AccountantExportLabels = .english) -> String {
        var lines = [line(documentColumns)]
        for exported in data.documents {
            lines.append(line(documentRow(exported, labels: labels)))
        }
        return lines.joined()
    }

    /// The Payments CSV: a header, then one row per payment dated in the month.
    public static func payments(_ data: AccountantExportData, labels: AccountantExportLabels = .english) -> String {
        var lines = [line(paymentColumns)]
        for exported in data.payments {
            let payment = exported.payment
            lines.append(line([
                date(payment.paidOn),
                text(exported.documentNumber),
                text(exported.documentKind.title(language: .czech)),
                text(exported.customerName),
                text(labels.paymentKind(payment.kind)),
                amount(payment.amount.amount, scale: payment.amount.currency.minorUnits),
                payment.amount.currency.code,
                text(exported.receiptNumber ?? ""),
                text(labels.paymentSource(payment)),
                text(payment.note ?? ""),
            ]))
        }
        return lines.joined()
    }

    static func documentRow(_ exported: ExportedDocument, labels: AccountantExportLabels) -> [String] {
        let document = exported.document
        let totals = exported.totals
        let scale = document.currency.minorUnits
        let customer = document.customer
        let isTax = document.kind.isTaxDocument
        var row: [String] = [
            text(document.number ?? ""),
            text(document.kind.title(language: .czech)),
            isTax ? yes : no,
            date(document.issueDate),
            isTax ? date(document.taxPoint) : "",
            date(document.dueDate),
            text(labels.status(exported.state)),
            text(customer.name),
            customer.identificationNumber?.digits ?? "",
            text(customer.vatIdentifier?.value ?? ""),
            text(customer.address.countryCode),
            text(treatmentText(document)),
            document.currency.code,
            amount(totals.totalGross, scale: scale),
        ]
        row += rateColumns(exported)
        if document.currency != .czk, let rate = document.exchangeRate {
            row += [
                decimal((rate.czkPerAmount / Decimal(rate.amount)).plainString(minimumFractionDigits: 3)),
                date(rate.validFor),
                text(labels.rateSource(rate.source)),
                rate.validFor < document.exchangeRateDay ? yes : no,
            ]
        } else {
            row += ["", "", "", ""]
        }
        row.append(text(exported.relatedNumbers.joined(separator: ", ")))
        row += deductionColumns(document, totals: totals)
        if exported.payments.isEmpty {
            row += ["", ""]
        } else {
            let paid = exported.payments.reduce(Decimal(0)) { $0 + $1.amount.amount }
            let lastIncoming = exported.payments.filter(\.isIncoming).map(\.paidOn).max()
            row += [amount(paid, scale: scale), lastIncoming.map { date($0) } ?? ""]
        }
        row.append(text(exported.state.closure.map { labels.closure($0.kind) } ?? ""))
        return row
    }

    /// Base and VAT per rate after any advance deduction (the document's own tax base, § 37a ZDPH), in the
    /// document currency and in CZK. An advance request, which is not a tax document, fills none. A CZK figure
    /// that can't be computed (no exchange rate) stays empty.
    static func rateColumns(_ exported: ExportedDocument) -> [String] {
        let count = rateColumnNames.count
        guard exported.document.kind.isTaxDocument else { return Array(repeating: "", count: count * 2) }
        var values = [Decimal?](repeating: nil, count: count)
        var inCZK = [Decimal?](repeating: nil, count: count)
        var missingCZK = Set<Int>()
        func add(_ value: Decimal, czk: Decimal?, at slot: Int) {
            values[slot] = (values[slot] ?? 0) + value
            if let czk {
                inCZK[slot] = (inCZK[slot] ?? 0) + czk
            } else {
                missingCZK.insert(slot)
            }
        }
        for row in exported.totals.rows {
            let slots = Self.slots(row.treatment)
            add(row.taxableBase, czk: row.taxableBaseCZK, at: slots.base)
            if let vatSlot = slots.vat {
                add(row.taxableVAT, czk: row.taxableVATCZK, at: vatSlot)
            }
        }
        let scale = exported.document.currency.minorUnits
        let own = values.map { $0.map { amount($0, scale: scale) } ?? "" }
        let czk = inCZK.enumerated().map { pair -> String in
            guard !missingCZK.contains(pair.offset), let value = pair.element else { return "" }
            return amount(value, scale: 2)
        }
        return own + czk
    }

    /// The columns of a treatment: Base21/VAT21, Base12/VAT12, Base0, BaseExempt (§ 64 goods and other
    /// exemptions), BaseRC, BaseOutsideEU. The 10 % rate (2015–2023) can't be issued any more; it would go
    /// with the reduced rate.
    static func slots(_ treatment: VATTreatment) -> (base: Int, vat: Int?) {
        switch treatment {
        case .taxable(let kind):
            switch kind {
            case .standard: return (0, 1)
            case .reduced, .secondReduced: return (2, 3)
            case .zero: return (4, nil)
            }
        case .intraCommunityGoods, .exempt: return (5, nil)
        case .reverseChargeEU: return (6, nil)
        case .outsideEU: return (7, nil)
        }
    }

    /// DeductedAdvance: what a final invoice deducts, the advances taxed on payment tax documents (gross) plus
    /// those paid on § 64 goods; DeductedVAT_CZK: the VAT of the deducted payment tax documents in CZK, at the
    /// rate each was taxed at. An advance paid on § 64 goods had no tax document and no VAT, so it leaves
    /// DeductedVAT_CZK empty (screens-flows.md §2h).
    static func deductionColumns(_ document: Document, totals: DocumentTotals) -> [String] {
        guard document.kind.deductsAdvances else { return ["", ""] }
        let deductions = document.advanceDeductions
        let deducted = totals.deductedBase + totals.deductedVAT + totals.paidInAdvance
        guard !deductions.isEmpty || totals.paidInAdvance != 0 else { return ["", ""] }
        let scale = document.currency.minorUnits
        guard !deductions.isEmpty else { return [amount(deducted, scale: scale), ""] }
        var vatCZK = Decimal(0)
        for deduction in deductions {
            if document.currency == .czk {
                vatCZK += deduction.vat
            } else if let rate = deduction.exchangeRate {
                vatCZK += rate.toCZK(deduction.vat, scale: 2)
            } else {
                return [amount(deducted, scale: scale), ""]
            }
        }
        return [amount(deducted, scale: scale), amount(vatCZK, scale: 2)]
    }

    /// "DPH 21 %, přenesení daňové povinnosti": the printed Czech treatment text of each treatment, in line order.
    static func treatmentText(_ document: Document) -> String {
        document.treatments.map { treatment -> String in
            var rate: VATRate?
            if case .taxable(let kind) = treatment {
                rate = CzechVATRates.rate(kind, on: document.taxPoint)
            }
            let note = Document.treatmentNote(treatment, rate: rate, language: .czech)
            if case .exempt(let reference) = treatment, !reference.isEmpty {
                return note + " (" + reference + ")"
            }
            return note
        }
        .joined(separator: ", ")
    }

    // MARK: Format

    /// The file's bytes: UTF-8 with a byte order mark, so Excel reads the Czech letters.
    public static func encoded(_ text: String) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    static func line(_ fields: [String]) -> String {
        fields.map(quoted).joined(separator: delimiter) + lineEnd
    }

    /// A field with the delimiter, a quote or a line break is quoted, its quotes doubled (RFC 4180).
    static func quoted(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Free text (names, notes, numbers typed by the user): one that starts like a spreadsheet formula gets an
    /// apostrophe in front, so opening the file never runs it.
    static func text(_ value: String) -> String {
        guard let first = value.first, "=+-@\t\r".contains(first) else { return value }
        return "'" + value
    }

    /// "1234,50": the decimal comma, no grouping, `scale` decimals.
    static func amount(_ value: Decimal, scale: Int) -> String {
        decimal(value.rounded(scale: scale).plainString(minimumFractionDigits: scale))
    }

    static func decimal(_ plain: String) -> String {
        plain.replacingOccurrences(of: ".", with: ",")
    }

    /// "05.11.2026".
    static func date(_ day: CalendarDay) -> String {
        func two(_ value: Int) -> String { value < 10 ? "0" + String(value) : String(value) }
        return two(day.day) + "." + two(day.month) + "." + String(day.year)
    }
}
