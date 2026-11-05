import Foundation
import Testing
@testable import InvoicingCore

@Suite struct VATRateTests {
    @Test func ratesByPeriod() {
        #expect(CzechVATRates.rate(.standard, on: day("2026-11-05"))?.percent == 21)
        #expect(CzechVATRates.rate(.reduced, on: day("2026-11-05"))?.percent == 12)
        #expect(CzechVATRates.rate(.secondReduced, on: day("2026-11-05")) == nil)
        #expect(CzechVATRates.rate(.zero, on: day("2026-11-05"))?.percent == 0)
        #expect(CzechVATRates.rate(.reduced, on: day("2023-12-31"))?.percent == 15)
        #expect(CzechVATRates.rate(.secondReduced, on: day("2023-12-31"))?.percent == 10)
        #expect(CzechVATRates.rate(.reduced, on: day("2024-01-01"))?.percent == 12)
        #expect(CzechVATRates.rate(.secondReduced, on: day("2014-12-31")) == nil)
        #expect(CzechVATRates.rate(.secondReduced, on: day("2015-01-01"))?.percent == 10)
        #expect(CzechVATRates.rate(.standard, on: day("2012-12-31")) == nil)
        #expect(CzechVATRates.rates(on: day("2026-01-01")).map(\.kind) == [.standard, .reduced, .zero])
    }

    @Test func multiplierAndCoefficient() {
        let standard = VATRate(kind: .standard, percent: 21)
        #expect(standard.multiplier == d("0.21"))
        #expect(standard.coefficient == d("1.21"))
        #expect(VATRate(kind: .reduced, percent: 12).coefficient == d("1.12"))
    }
}

@Suite struct VATTreatmentTests {
    @Test func flags() {
        #expect(VATTreatment.taxable(.standard).chargesVAT)
        #expect(!VATTreatment.reverseChargeEU.chargesVAT)
        #expect(VATTreatment.reverseChargeEU.requiresCustomerVATID)
        #expect(VATTreatment.reverseChargeEU.reportedInECSalesList)
        #expect(!VATTreatment.outsideEU.requiresCustomerVATID)
        #expect(!VATTreatment.outsideEU.reportedInECSalesList)
        #expect(!VATTreatment.intraCommunityGoods.chargesVAT)
        #expect(VATTreatment.intraCommunityGoods.requiresCustomerVATID)
        #expect(VATTreatment.intraCommunityGoods.reportedInECSalesList)
        #expect(VATTreatment.intraCommunityGoods.groupingKey != VATTreatment.reverseChargeEU.groupingKey)
        #expect(!VATTreatment.exempt(reference: "§ 64").requiresCustomerVATID)
        #expect(!VATTreatment.exempt(reference: "§ 51").chargesVAT)
        #expect(VATTreatment.taxable(.standard).groupingKey != VATTreatment.taxable(.reduced).groupingKey)
        #expect(VATTreatment.exempt(reference: "a").groupingKey != VATTreatment.exempt(reference: "b").groupingKey)
    }

    @Test func codable() throws {
        let all: [VATTreatment] = [.taxable(.reduced), .intraCommunityGoods, .reverseChargeEU, .outsideEU, .exempt(reference: "§ 51 odst. 1 písm. a)")]
        let data = try JSONEncoder().encode(all)
        let back = try JSONDecoder().decode([VATTreatment].self, from: data)
        #expect(back == all)
    }
}

@Suite struct VATCalculatorTests {
    let today = day("2026-11-05")

    @Test func netPricingGroupsByRate() throws {
        let result = try VATCalculator.compute(lines: [
            LineInput(quantity: 2, unitPrice: 1000, treatment: .taxable(.standard)),
            LineInput(quantity: 1, unitPrice: 500, treatment: .taxable(.reduced)),
            LineInput(quantity: 1, unitPrice: 100, treatment: .taxable(.standard)),
        ], pricing: .net, on: today)
        #expect(result.lines.map(\.net) == [2000, 500, 100])
        #expect(result.lines.map(\.vat) == [420, 60, 21])
        #expect(result.lines.map(\.gross) == [2420, 560, 121])
        #expect(result.groups.count == 2)
        #expect(result.groups[0].treatment == .taxable(.standard))
        #expect(result.groups[0].rate?.percent == 21)
        #expect(result.groups[0].base == 2100)
        #expect(result.groups[0].vat == 441)
        #expect(result.groups[0].gross == 2541)
        #expect(result.groups[1].treatment == .taxable(.reduced))
        #expect(result.groups[1].base == 500)
        #expect(result.groups[1].vat == 60)
        #expect(result.totalBase == 2600)
        #expect(result.totalVAT == 501)
        #expect(result.totalGross == 3101)
    }

    @Test func taxIsComputedFromTheSummedBaseNotFromLines() throws {
        // § 37 písm. a) ZDPH: tax = base × rate. Three lines of 0.35: per line 0.0735 → 0.07, but the
        // tax on the summed base 1.05 is 0.2205 → 0.22, not 3 × 0.07 = 0.21.
        let line = LineInput(quantity: 1, unitPrice: d("0.35"), treatment: .taxable(.standard))
        let result = try VATCalculator.compute(lines: [line, line, line], pricing: .net, on: today)
        #expect(result.lines.map(\.vat) == [d("0.07"), d("0.07"), d("0.07")])
        #expect(result.groups[0].base == d("1.05"))
        #expect(result.groups[0].vat == d("0.22"))
        #expect(result.totalGross == d("1.27"))
    }

    @Test func grossPricingUsesCoefficient() throws {
        let result = try VATCalculator.compute(lines: [
            LineInput(quantity: 1, unitPrice: 121, treatment: .taxable(.standard)),
            LineInput(quantity: 1, unitPrice: 1210, treatment: .taxable(.reduced)),
        ], pricing: .gross, on: today)
        #expect(result.lines[0].net == 100)
        #expect(result.lines[0].vat == 21)
        #expect(result.lines[0].gross == 121)
        #expect(result.lines[1].net == d("1080.36"))   // 1210 / 1.12 = 1080.3571…
        #expect(result.lines[1].vat == d("129.64"))
        #expect(result.groups[0].gross == 121)
        #expect(result.groups[1].gross == 1210)
        #expect(result.totalGross == 1331)
        #expect(result.totalBase == d("1180.36"))
        #expect(result.totalVAT == d("150.64"))
    }

    @Test func grossPricingSumsGrossBeforeDividing() throws {
        // Three gross lines of 1.00 at 21 %: per line base 0.83 (0.8264…), but the group divides the
        // summed gross 3.00 → base 2.48 (2.4793…), tax 0.52. Totals come from the group.
        let line = LineInput(quantity: 1, unitPrice: 1, treatment: .taxable(.standard))
        let result = try VATCalculator.compute(lines: [line, line, line], pricing: .gross, on: today)
        #expect(result.lines.map(\.net) == [d("0.83"), d("0.83"), d("0.83")])
        #expect(result.groups[0].base == d("2.48"))
        #expect(result.groups[0].vat == d("0.52"))
        #expect(result.totalGross == 3)
    }

    @Test func reverseChargeAndOutsideEUCarryNoTax() throws {
        let result = try VATCalculator.compute(lines: [
            LineInput(quantity: 10, unitPrice: d("95.5"), treatment: .reverseChargeEU),
            LineInput(quantity: 1, unitPrice: 200, treatment: .outsideEU),
            LineInput(quantity: 1, unitPrice: 50, treatment: .reverseChargeEU),
        ], pricing: .net, on: today)
        #expect(result.groups.count == 2)
        #expect(result.groups[0].treatment == .reverseChargeEU)
        #expect(result.groups[0].rate == nil)
        #expect(result.groups[0].base == 1005)
        #expect(result.groups[0].vat == 0)
        #expect(result.groups[1].treatment == .outsideEU)
        #expect(result.groups[1].base == 200)
        #expect(result.totalBase == 1205)
        #expect(result.totalVAT == 0)
        #expect(result.totalGross == 1205)
        // Gross pricing changes nothing for lines without VAT.
        let gross = try VATCalculator.compute(lines: [LineInput(quantity: 1, unitPrice: 200, treatment: .reverseChargeEU)], pricing: .gross, on: today)
        #expect(gross.totalBase == 200)
        #expect(gross.totalGross == 200)
    }

    @Test func exemptLinesGroupByReference() throws {
        let result = try VATCalculator.compute(lines: [
            LineInput(quantity: 1, unitPrice: 100, treatment: .exempt(reference: "§ 51")),
            LineInput(quantity: 1, unitPrice: 100, treatment: .exempt(reference: "§ 52")),
            LineInput(quantity: 1, unitPrice: 100, treatment: .exempt(reference: "§ 51")),
        ], pricing: .net, on: today)
        #expect(result.groups.count == 2)
        #expect(result.groups[0].base == 200)
        #expect(result.groups[1].base == 100)
        #expect(result.totalVAT == 0)
    }

    @Test func discountsAndQuantities() throws {
        let result = try VATCalculator.compute(lines: [
            LineInput(quantity: 1, unitPrice: 1000, discountPercent: 10, treatment: .taxable(.standard)),
            LineInput(quantity: 3, unitPrice: d("19.99"), treatment: .taxable(.standard)),
            LineInput(quantity: d("1.5"), unitPrice: d("33.333"), treatment: .taxable(.standard)),
            LineInput(quantity: 0, unitPrice: 999, treatment: .taxable(.standard)),
            LineInput(quantity: 1, unitPrice: 80, discountPercent: 100, treatment: .taxable(.standard)),
        ], pricing: .net, on: today)
        #expect(result.lines.map(\.net) == [900, d("59.97"), 50, 0, 0])
        #expect(result.lines[1].vat == d("12.59"))   // 59.97 × 0.21 = 12.5937
        #expect(result.groups[0].base == d("1009.97"))
        #expect(result.groups[0].vat == d("212.09"))  // 1009.97 × 0.21 = 212.0937
    }

    @Test func rejectsBadInput() {
        #expect(throws: VATCalculationError.invalidDiscount(101)) {
            try VATCalculator.compute(lines: [LineInput(quantity: 1, unitPrice: 1, discountPercent: 101, treatment: .taxable(.standard))], pricing: .net, on: today)
        }
        #expect(throws: VATCalculationError.invalidDiscount(-1)) {
            try VATCalculator.compute(lines: [LineInput(quantity: 1, unitPrice: 1, discountPercent: -1, treatment: .taxable(.standard))], pricing: .net, on: today)
        }
        #expect(throws: VATCalculationError.negativeQuantity(-1)) {
            try VATCalculator.compute(lines: [LineInput(quantity: -1, unitPrice: 1, treatment: .taxable(.standard))], pricing: .net, on: today)
        }
        #expect(throws: VATCalculationError.rateNotInForce(.secondReduced, today)) {
            try VATCalculator.compute(lines: [LineInput(quantity: 1, unitPrice: 1, treatment: .taxable(.secondReduced))], pricing: .net, on: today)
        }
    }

    @Test func emptyDocument() throws {
        let result = try VATCalculator.compute(lines: [], pricing: .net, on: today)
        #expect(result.groups.isEmpty)
        #expect(result.totalGross == 0)
    }

    @Test func historicalRatesApply() throws {
        let result = try VATCalculator.compute(lines: [
            LineInput(quantity: 1, unitPrice: 100, treatment: .taxable(.reduced)),
            LineInput(quantity: 1, unitPrice: 100, treatment: .taxable(.secondReduced)),
        ], pricing: .net, on: day("2020-06-15"))
        #expect(result.groups[0].vat == 15)
        #expect(result.groups[1].vat == 10)
    }

    @Test func wholeCrownScale() throws {
        // A CZK document rounded to whole crowns uses scale 0; the rounding itself is a later decision.
        let result = try VATCalculator.compute(lines: [
            LineInput(quantity: 1, unitPrice: d("999.5"), treatment: .taxable(.standard)),
        ], pricing: .net, on: today, scale: 0)
        #expect(result.lines[0].net == 1000)
        #expect(result.groups[0].vat == 210)
        #expect(result.totalGross == 1210)
    }
}
