import Foundation

/// One row of the VAT summary (rekapitulace DPH) of a document: one VAT treatment and rate.
public struct VATSummaryRow: Hashable, Sendable {
    public let treatment: VATTreatment
    /// The rate in force on the tax point; nil for treatments without Czech VAT.
    public let rate: VATRate?
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
/// the advance bases, and the VAT is computed from that difference (§ 37a odst. 1 and 2 ZDPH). CZK
/// equivalents convert the base and the VAT of each row separately and round them to haléře, so the CZK
/// summary adds up row by row.
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
    /// What the customer pays: taxable base plus VAT; negative when the advances exceed the supply.
    public let amountDue: Decimal
    public let taxableBaseCZK: Decimal?
    /// The VAT in Czech crowns (§ 29 odst. 1 písm. l) ZDPH); equals `taxableVAT` on CZK documents.
    public let taxableVATCZK: Decimal?
    public let exchangeRate: ExchangeRate?

    public var amountDueMoney: Money { Money(amountDue, currency) }

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
        let isCZK = document.currency == .czk
        let rate = isCZK ? nil : document.exchangeRate
        func czk(_ value: Decimal) -> Decimal? {
            if isCZK { return value }
            guard let rate else { return nil }
            return rate.toCZK(value, scale: 2)
        }

        // Advances per treatment (§ 37a ZDPH), in order of first appearance.
        var deductedBaseByKey: [String: Decimal] = [:]
        var deductedVATByKey: [String: Decimal] = [:]
        var deductionRateByKey: [String: Decimal] = [:]
        var deductionTreatmentByKey: [String: VATTreatment] = [:]
        var deductionOrder: [String] = []
        if document.kind.deductsAdvances {
            for deduction in document.advanceDeductions {
                let key = deduction.treatment.groupingKey
                if deductionTreatmentByKey[key] == nil {
                    deductionTreatmentByKey[key] = deduction.treatment
                    deductionOrder.append(key)
                }
                deductedBaseByKey[key, default: 0] += deduction.base
                deductedVATByKey[key, default: 0] += deduction.vat
                if let percent = deduction.ratePercent {
                    deductionRateByKey[key] = percent
                }
            }
        }

        var rows: [VATSummaryRow] = []
        var seenKeys: Set<String> = []
        for group in amounts.groups {
            let key = group.treatment.groupingKey
            seenKeys.insert(key)
            rows.append(Self.row(treatment: group.treatment, rate: group.rate, base: group.base, vat: group.vat,
                                 deductedBase: deductedBaseByKey[key] ?? 0, deductedVAT: deductedVATByKey[key] ?? 0,
                                 deductionRate: deductionRateByKey[key], scale: scale, czk: czk))
        }
        // Advances taxed under a treatment that has no line on the final invoice: a deduction-only row.
        for key in deductionOrder where !seenKeys.contains(key) {
            guard let treatment = deductionTreatmentByKey[key] else { continue }
            var currentRate: VATRate? = nil
            if case .taxable(let kind) = treatment {
                currentRate = CzechVATRates.rate(kind, on: day)
            }
            rows.append(Self.row(treatment: treatment, rate: currentRate, base: 0, vat: 0,
                                 deductedBase: deductedBaseByKey[key] ?? 0, deductedVAT: deductedVATByKey[key] ?? 0,
                                 deductionRate: deductionRateByKey[key], scale: scale, czk: czk))
        }

        let totalBase = rows.reduce(Decimal(0)) { $0 + $1.base }
        let totalVAT = rows.reduce(Decimal(0)) { $0 + $1.vat }
        let deductedBase = rows.reduce(Decimal(0)) { $0 + $1.deductedBase }
        let deductedVAT = rows.reduce(Decimal(0)) { $0 + $1.deductedVAT }
        let taxableBase = rows.reduce(Decimal(0)) { $0 + $1.taxableBase }
        let taxableVAT = rows.reduce(Decimal(0)) { $0 + $1.taxableVAT }

        return DocumentTotals(
            currency: document.currency,
            lines: amounts.lines,
            rows: rows,
            totalBase: totalBase,
            totalVAT: totalVAT,
            totalGross: totalBase + totalVAT,
            deductedBase: deductedBase,
            deductedVAT: deductedVAT,
            taxableBase: taxableBase,
            taxableVAT: taxableVAT,
            amountDue: taxableBase + taxableVAT,
            taxableBaseCZK: Self.sum(rows.map(\.taxableBaseCZK)),
            taxableVATCZK: Self.sum(rows.map(\.taxableVATCZK)),
            exchangeRate: rate
        )
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
                            deductedBase: Decimal, deductedVAT: Decimal, deductionRate: Decimal?,
                            scale: Int, czk: (Decimal) -> Decimal?) -> VATSummaryRow {
        let taxableBase = base - deductedBase
        let taxableVAT: Decimal
        if deductedBase == 0 && deductedVAT == 0 {
            // No deduction: the VAT is exactly the calculator's, so a regular invoice never changes.
            taxableVAT = vat
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
        }
        return VATSummaryRow(
            treatment: treatment,
            rate: rate,
            base: base,
            vat: vat,
            gross: base + vat,
            deductedBase: deductedBase,
            deductedVAT: deductedVAT,
            taxableBase: taxableBase,
            taxableVAT: taxableVAT,
            taxableBaseCZK: czk(taxableBase),
            taxableVATCZK: czk(taxableVAT)
        )
    }
}
