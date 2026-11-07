import Foundation
import Testing
@testable import InvoicingCore

@Suite struct PaymentToleranceTests {
    @Test func oneCrownForCZKAndOneCentOtherwise() {
        #expect(PaymentTolerance.amount(for: .czk) == 1)
        #expect(PaymentTolerance.amount(for: .eur) == d("0.01"))
        #expect(PaymentTolerance.matches(Money(d("12100"), .czk), Money(d("12099"), .czk)))
        #expect(PaymentTolerance.matches(Money(d("12100"), .czk), Money(d("12101.00"), .czk)))
        #expect(!PaymentTolerance.matches(Money(d("12100"), .czk), Money(d("12101.01"), .czk)))
        #expect(PaymentTolerance.matches(Money(d("1000"), .eur), Money(d("999.99"), .eur)))
        #expect(!PaymentTolerance.matches(Money(d("1000"), .eur), Money(d("999.98"), .eur)))
        #expect(PaymentTolerance.matches(Money(d("10.5"), .usd), Money(d("10.51"), .usd)))
    }

    @Test func differentCurrenciesNeverMatch() {
        #expect(!PaymentTolerance.matches(Money(d("100"), .czk), Money(d("100"), .eur)))
    }
}
