import Foundation

/// Whether unit prices on a document are entered without VAT (net) or including VAT (gross).
public enum PricingMode: String, Sendable, Codable {
    /// Tax = base × rate (§ 37 písm. a) ZDPH).
    case net
    /// Base = gross ÷ coefficient (1.21 or 1.12), tax = gross − base (§ 37 písm. b) ZDPH).
    case gross
}

/// One line as entered by the user.
public struct LineInput: Hashable, Sendable {
    public var quantity: Decimal
    /// Net or gross per the document's `PricingMode`.
    public var unitPrice: Decimal
    /// 0...100; a discount on the line total, shown separately on the document (§ 29 odst. 1 písm. i)).
    public var discountPercent: Decimal
    public var treatment: VATTreatment

    public init(quantity: Decimal, unitPrice: Decimal, discountPercent: Decimal = 0, treatment: VATTreatment) {
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discountPercent = discountPercent
        self.treatment = treatment
    }
}

/// Computed amounts of one line, rounded to the document's scale.
public struct LineAmounts: Hashable, Sendable {
    public let treatment: VATTreatment
    public let rate: VATRate?
    /// Line total before VAT, after discount.
    public let net: Decimal
    /// VAT of this line alone; informational, the binding tax is per `VATGroup`.
    public let vat: Decimal
    public let gross: Decimal
}

/// One row of the VAT summary ("rekapitulace DPH"): base and tax per rate or treatment.
public struct VATGroup: Hashable, Sendable {
    public let treatment: VATTreatment
    public let rate: VATRate?
    public let base: Decimal
    public let vat: Decimal
    public var gross: Decimal { base + vat }
}

public struct DocumentAmounts: Hashable, Sendable {
    public let lines: [LineAmounts]
    public let groups: [VATGroup]
    public let totalBase: Decimal
    public let totalVAT: Decimal
    public let totalGross: Decimal
}

public enum VATCalculationError: Error, Equatable, Sendable {
    case rateNotInForce(VATRateKind, CalendarDay)
    case invalidDiscount(Decimal)
    case negativeQuantity(Decimal)
}

/// Computes line amounts and the VAT summary of a document.
///
/// Tax per rate is computed on the summed base of that rate (§ 37 písm. a) ZDPH: "ze základu daně"),
/// not by adding up per-line tax, so the summary never drifts by a haléř from the rounded lines.
/// Per-line VAT is informational only. Rounding is half away from zero to `scale` decimals.
public enum VATCalculator {
    public static func compute(
        lines: [LineInput],
        pricing: PricingMode,
        on day: CalendarDay,
        scale: Int = 2
    ) throws -> DocumentAmounts {
        var lineAmounts: [LineAmounts] = []
        lineAmounts.reserveCapacity(lines.count)

        for line in lines {
            guard line.quantity >= 0 else { throw VATCalculationError.negativeQuantity(line.quantity) }
            guard line.discountPercent >= 0, line.discountPercent <= 100 else {
                throw VATCalculationError.invalidDiscount(line.discountPercent)
            }
            let discountFactor = 1 - line.discountPercent / 100
            let lineTotal = (line.quantity * line.unitPrice * discountFactor).rounded(scale: scale)

            let resolvedRate: VATRate?
            if case .taxable(let kind) = line.treatment {
                guard let found = CzechVATRates.rate(kind, on: day) else {
                    throw VATCalculationError.rateNotInForce(kind, day)
                }
                resolvedRate = found
            } else {
                resolvedRate = nil
            }

            guard let rate = resolvedRate else {
                lineAmounts.append(LineAmounts(treatment: line.treatment, rate: nil, net: lineTotal, vat: 0, gross: lineTotal))
                continue
            }

            switch pricing {
            case .net:
                let vat = (lineTotal * rate.multiplier).rounded(scale: scale)
                lineAmounts.append(LineAmounts(treatment: line.treatment, rate: rate, net: lineTotal, vat: vat, gross: lineTotal + vat))
            case .gross:
                let base = (lineTotal / rate.coefficient).rounded(scale: scale)
                lineAmounts.append(LineAmounts(treatment: line.treatment, rate: rate, net: base, vat: lineTotal - base, gross: lineTotal))
            }
        }

        // Group in order of first appearance.
        var order: [String] = []
        var netByKey: [String: Decimal] = [:]
        var grossByKey: [String: Decimal] = [:]
        var meta: [String: (treatment: VATTreatment, rate: VATRate?)] = [:]
        for amounts in lineAmounts {
            let key = amounts.treatment.groupingKey
            if meta[key] == nil {
                order.append(key)
                meta[key] = (treatment: amounts.treatment, rate: amounts.rate)
            }
            netByKey[key, default: 0] += amounts.net
            grossByKey[key, default: 0] += amounts.gross
        }

        var groups: [VATGroup] = []
        for key in order {
            guard let entry = meta[key] else { continue }
            guard let rate = entry.rate else {
                groups.append(VATGroup(treatment: entry.treatment, rate: nil, base: netByKey[key] ?? 0, vat: 0))
                continue
            }
            switch pricing {
            case .net:
                let base = netByKey[key] ?? 0
                let vat = (base * rate.multiplier).rounded(scale: scale)
                groups.append(VATGroup(treatment: entry.treatment, rate: rate, base: base, vat: vat))
            case .gross:
                let gross = grossByKey[key] ?? 0
                let base = (gross / rate.coefficient).rounded(scale: scale)
                groups.append(VATGroup(treatment: entry.treatment, rate: rate, base: base, vat: gross - base))
            }
        }

        let totalBase = groups.reduce(Decimal(0)) { $0 + $1.base }
        let totalVAT = groups.reduce(Decimal(0)) { $0 + $1.vat }
        return DocumentAmounts(
            lines: lineAmounts,
            groups: groups,
            totalBase: totalBase,
            totalVAT: totalVAT,
            totalGross: totalBase + totalVAT
        )
    }
}
