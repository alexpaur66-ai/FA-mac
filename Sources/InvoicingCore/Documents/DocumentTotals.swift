import Foundation

/// One row of the VAT summary (rekapitulace DPH) of a document: one VAT treatment and rate.
public struct VATSummaryRow: Hashable, Sendable {
    public let treatment: VATTreatment
    /// The rate in force on the tax point (the day of supply); nil for treatments without Czech VAT.
    public let rate: VATRate?
    /// The percentage `taxableVAT` was computed at, which is what the document prints next to the row's
    /// base and VAT (§ 29 odst. 1 písm. k) ZDPH): the rate of the day of supply, or the rate applied to the
    /// advances for a negative difference (§ 37a odst. 2 písm. b) ZDPH). Nil without Czech VAT.
    public let appliedRatePercent: Decimal?
    /// Base, VAT and gross of the lines, before any advance deduction.
    public let base: Decimal
    public let vat: Decimal
    public let gross: Decimal
    /// Advances deducted on a final invoice (§ 37a ZDPH); zero elsewhere.
    public let deductedBase: Decimal
    public let deductedVAT: Decimal
    /// What this document taxes: base and VAT after the deduction (§ 29 odst. 1 písm. j) and l) ZDPH).
    public let taxableBase: Decimal
    public let taxableVAT: Decimal
    /// CZK equivalents of `taxableBase` and `taxableVAT` (§ 4 odst. 8 ZDPH); nil when the document is in a
    /// foreign currency and has no exchange rate.
    public let taxableBaseCZK: Decimal?
    public let taxableVATCZK: Decimal?
    /// The rate the CZK equivalents were converted at: the document's rate, or for a negative difference
    /// the rate that was applied to the advances (§ 37a odst. 2 písm. b) ZDPH). Nil on CZK documents and
    /// when no rate is available.
    public let exchangeRate: ExchangeRate?
    /// What the customer pays for this row. When the advances were taxed at the row's own rate it is the
    /// gross of the lines minus the gross of the advances actually paid, so a haléř of rounding in the
    /// recomputed VAT never changes the balance; when the rates differ it is `taxableGross` (§ 37a ZDPH).
    public let amountDue: Decimal

    public var taxableGross: Decimal { taxableBase + taxableVAT }
}

public enum DocumentAmountError: Error, Equatable, Sendable {
    /// The exchange rate quotes another currency than the document's.
    case exchangeRateCurrencyMismatch(rate: Currency, document: Currency)
}

/// The amounts of a document: per line, per VAT rate, totals, advance deductions and CZK equivalents.
///
/// Line and group arithmetic is `VATCalculator` (§ 37 ZDPH, docs/adr/0002). A final invoice deducts the
/// advances per treatment: the tax base is the difference between the base of the supply and the sum of
/// the advance bases, and the VAT is computed from that difference (§ 37a odst. 1 and 2 ZDPH); an advance
/// taxed under another rate kind is deducted from the only taxable supply (see `rowKey`). CZK
/// equivalents convert the base and the VAT of each row separately and round them to haléře, so the CZK
/// summary adds up row by row; a negative difference is converted at the exchange rate applied to the
/// advances (§ 37a odst. 2 písm. b) ZDPH), every other row at the document's rate.
public struct DocumentTotals: Hashable, Sendable {
    public let currency: Currency
    public let lines: [LineAmounts]
    public let rows: [VATSummaryRow]
    /// Sums over the lines, before deductions.
    public let totalBase: Decimal
    public let totalVAT: Decimal
    public let totalGross: Decimal
    /// Sums of the advance deductions.
    public let deductedBase: Decimal
    public let deductedVAT: Decimal
    /// Sums after deduction: the tax base and the VAT of this document.
    public let taxableBase: Decimal
    public let taxableVAT: Decimal
    /// What the customer pays: the sum of the rows' `amountDue`, which is the gross of the supply minus
    /// the gross of the advances paid, or the taxable base plus VAT where § 37a changed the rate; negative
    /// when the advances exceed the supply.
    public let amountDue: Decimal
    public let taxableBaseCZK: Decimal?
    /// The VAT in Czech crowns (§ 29 odst. 1 písm. l) ZDPH); equals `taxableVAT` on CZK documents.
    public let taxableVATCZK: Decimal?
    /// The document's own rate (§ 4 odst. 8 ZDPH); nil on CZK documents. Rows with a negative difference
    /// may carry another one, see `VATSummaryRow.exchangeRate`.
    public let exchangeRate: ExchangeRate?

    public var amountDueMoney: Money { Money(amountDue, currency) }

    /// The distinct rates of the advances that rows with a negative difference were converted at, other
    /// than the document's own rate, in row order: what the document explains in a clause.
    public var advanceExchangeRates: [ExchangeRate] {
        var result: [ExchangeRate] = []
        for row in rows {
            guard let rate = row.exchangeRate, rate != exchangeRate, !result.contains(rate) else { continue }
            result.append(rate)
        }
        return result
    }

    /// Computes the amounts of `document` on its tax point. Throws `VATCalculationError` for a rate that
    /// was not in force, a negative quantity or a bad discount, and `DocumentAmountError` for a rate in
    /// the wrong currency.
    public static func compute(for document: Document) throws -> DocumentTotals {
        let scale = document.currency.minorUnits
        let day = document.taxPoint
        let amounts = try VATCalculator.compute(lines: document.lines.map(\.input), pricing: document.pricing, on: day, scale: scale)

        if let rate = document.exchangeRate, rate.currency != document.currency {
            throw DocumentAmountError.exchangeRateCurrencyMismatch(rate: rate.currency, document: document.currency)
        }
        let currency = document.currency
        let documentRate = currency == .czk ? nil : document.exchangeRate

        // Advances per summary row (§ 37a ZDPH), in order of first appearance.
        let lineTreatments = amounts.groups.map(\.treatment)
        var deductionsByKey: [String: [AdvanceDeduction]] = [:]
        var deductionTreatmentByKey: [String: VATTreatment] = [:]
        var deductionOrder: [String] = []
        if document.kind.deductsAdvances {
            for deduction in document.advanceDeductions {
                let key = rowKey(for: deduction, lineTreatments: lineTreatments)
                if deductionTreatmentByKey[key] == nil {
                    deductionTreatmentByKey[key] = deduction.treatment
                    deductionOrder.append(key)
                }
                deductionsByKey[key, default: []].append(deduction)
            }
        }

        var rows: [VATSummaryRow] = []
        var seenKeys: Set<String> = []
        for group in amounts.groups {
            let key = group.treatment.groupingKey
            seenKeys.insert(key)
            rows.append(Self.row(treatment: group.treatment, rate: group.rate, base: group.base, vat: group.vat,
                                 deductions: deductionsByKey[key] ?? [], currency: currency, documentRate: documentRate, scale: scale))
        }
        // Advances taxed under a treatment that has no line on the final invoice: a deduction-only row.
        for key in deductionOrder where !seenKeys.contains(key) {
            guard let treatment = deductionTreatmentByKey[key] else { continue }
            var currentRate: VATRate? = nil
            if case .taxable(let kind) = treatment {
                currentRate = CzechVATRates.rate(kind, on: day)
            }
            rows.append(Self.row(treatment: treatment, rate: currentRate, base: 0, vat: 0,
                                 deductions: deductionsByKey[key] ?? [], currency: currency, documentRate: documentRate, scale: scale))
        }

        let totalBase = rows.reduce(Decimal(0)) { $0 + $1.base }
        let totalVAT = rows.reduce(Decimal(0)) { $0 + $1.vat }
        let deductedBase = rows.reduce(Decimal(0)) { $0 + $1.deductedBase }
        let deductedVAT = rows.reduce(Decimal(0)) { $0 + $1.deductedVAT }
        let taxableBase = rows.reduce(Decimal(0)) { $0 + $1.taxableBase }
        let taxableVAT = rows.reduce(Decimal(0)) { $0 + $1.taxableVAT }
        let amountDue = rows.reduce(Decimal(0)) { $0 + $1.amountDue }

        return DocumentTotals(
            currency: currency,
            lines: amounts.lines,
            rows: rows,
            totalBase: totalBase,
            totalVAT: totalVAT,
            totalGross: totalBase + totalVAT,
            deductedBase: deductedBase,
            deductedVAT: deductedVAT,
            taxableBase: taxableBase,
            taxableVAT: taxableVAT,
            amountDue: amountDue,
            taxableBaseCZK: Self.sum(rows.map(\.taxableBaseCZK)),
            taxableVATCZK: Self.sum(rows.map(\.taxableVATCZK)),
            exchangeRate: documentRate
        )
    }

    /// The key of the summary row an advance is deducted from (§ 37a odst. 1 ZDPH: one difference per
    /// supply). It is the key of the advance's own treatment, except for an advance taxed under another
    /// taxable rate kind than any line (e.g. a 2023 advance at the reduced 15 % for a supply now at the
    /// standard rate): when the document has exactly one taxable group, the advance is deducted from it.
    /// Otherwise it gets a deduction-only row and the validator warns. `lineTreatments` are the
    /// distinct treatments of the document's lines.
    static func rowKey(for deduction: AdvanceDeduction, lineTreatments: [VATTreatment]) -> String {
        let key = deduction.treatment.groupingKey
        guard deduction.treatment.chargesVAT, !lineTreatments.contains(where: { $0.groupingKey == key }) else { return key }
        let taxable = lineTreatments.filter(\.chargesVAT)
        guard taxable.count == 1, let only = taxable.first else { return key }
        return only.groupingKey
    }

    /// The exchange rate a negative difference is converted at (§ 37a odst. 2 písm. b) ZDPH): the one
    /// rate applied to all of the row's advances. Nil when a deduction carries no rate, or one in another
    /// currency, or the advances were taxed at different rates (§ 37a odst. 3, left to the accountant);
    /// the row then falls back to the document's rate and the validator warns.
    static func advanceExchangeRate(of deductions: [AdvanceDeduction], in currency: Currency) -> ExchangeRate? {
        var rates: [ExchangeRate] = []
        for deduction in deductions {
            guard let rate = deduction.exchangeRate, rate.currency == currency else { return nil }
            rates.append(rate)
        }
        guard let first = rates.first, rates.allSatisfy({ $0.czkPerUnit == first.czkPerUnit }) else { return nil }
        return first
    }

    /// Sum of CZK equivalents; nil as soon as one of them is missing.
    private static func sum(_ values: [Decimal?]) -> Decimal? {
        var total = Decimal(0)
        for value in values {
            guard let value else { return nil }
            total += value
        }
        return total
    }

    private static func row(treatment: VATTreatment, rate: VATRate?, base: Decimal, vat: Decimal,
                            deductions: [AdvanceDeduction], currency: Currency, documentRate: ExchangeRate?,
                            scale: Int) -> VATSummaryRow {
        let deductedBase = deductions.reduce(Decimal(0)) { $0 + $1.base }
        let deductedVAT = deductions.reduce(Decimal(0)) { $0 + $1.vat }
        let deductionPercents = Set(deductions.compactMap(\.ratePercent))
        // The rate of the advances: the last one taxed, as a single value for the negative difference.
        let deductionRate = deductions.compactMap(\.ratePercent).last
        let taxableBase = base - deductedBase
        let taxableVAT: Decimal
        let appliedRatePercent: Decimal?
        if deductedBase == 0 && deductedVAT == 0 {
            // No deduction: the VAT is exactly the calculator's, so a regular invoice never changes.
            taxableVAT = vat
            appliedRatePercent = rate?.percent
        } else {
            // § 37a odst. 2 ZDPH: a positive difference is taxed at the rate of the day of supply, a negative
            // one at the rate that was applied to the advance.
            let percent: Decimal?
            if taxableBase >= 0 {
                percent = rate?.percent ?? deductionRate
            } else {
                percent = deductionRate ?? rate?.percent
            }
            if let percent {
                taxableVAT = (taxableBase * percent / 100).rounded(scale: scale)
            } else {
                taxableVAT = 0
            }
            appliedRatePercent = percent
        }
        // § 37a odst. 2 ZDPH again for the conversion: a negative difference uses the exchange rate that
        // was applied to the advance, everything else the rate of the day of supply (the document's).
        let conversionRate: ExchangeRate?
        if currency == .czk {
            conversionRate = nil
        } else if taxableBase < 0, let advanceRate = advanceExchangeRate(of: deductions, in: currency) {
            conversionRate = advanceRate
        } else {
            conversionRate = documentRate
        }
        func czk(_ value: Decimal) -> Decimal? {
            if currency == .czk { return value }
            guard let conversionRate else { return nil }
            return conversionRate.toCZK(value, scale: 2)
        }
        // Advances taxed at the row's own rate: the customer pays the balance of what was asked and paid,
        // whatever haléř the recomputed VAT rounds to. Advances at another rate: § 37a moves the VAT.
        let sameRate = deductionPercents.allSatisfy { $0 == rate?.percent }
        let amountDue = sameRate ? base + vat - deductedBase - deductedVAT : taxableBase + taxableVAT
        return VATSummaryRow(
            treatment: treatment,
            rate: rate,
            appliedRatePercent: appliedRatePercent,
            base: base,
            vat: vat,
            gross: base + vat,
            deductedBase: deductedBase,
            deductedVAT: deductedVAT,
            taxableBase: taxableBase,
            taxableVAT: taxableVAT,
            taxableBaseCZK: czk(taxableBase),
            taxableVATCZK: czk(taxableVAT),
            exchangeRate: conversionRate,
            amountDue: amountDue
        )
    }
}
