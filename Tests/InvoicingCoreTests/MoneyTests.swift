import Foundation
import Testing
@testable import InvoicingCore

@Suite struct MoneyTests {
    @Test func minorUnitsRoundTrip() {
        let amount = Money(minorUnits: 12345, currency: .eur)
        #expect(amount.amount == d("123.45"))
        #expect(amount.minorUnits == 12345)
        #expect(Money(minorUnits: -5, currency: .czk).amount == d("-0.05"))
        #expect(Money(d("0.005"), .eur).minorUnits == 1)
        #expect(Money(d("-0.005"), .eur).minorUnits == -1)
        #expect(Money(d("1.004"), .eur).minorUnits == 100)
        #expect(Money(minorUnits: 9_999_999_999_999, currency: .czk).minorUnits == 9_999_999_999_999)
    }

    @Test func roundsToCurrencyMinorUnits() {
        #expect(Money(d("10.005"), .eur).rounded().amount == d("10.01"))
        #expect(Money(d("10.004"), .eur).rounded().amount == d("10.00"))
        let yen = Currency.known("JPY")
        #expect(yen.minorUnits == 0)
        #expect(Money(d("10.5"), yen).rounded().amount == 11)
        #expect(Money(d("10.5"), yen).minorUnits == 11)
    }

    @Test func arithmeticKeepsPrecisionUntilRounded() {
        let a = Money(d("0.1"), .eur)
        let b = Money(d("0.2"), .eur)
        #expect((a + b).amount == d("0.3"))
        #expect((b - a).amount == d("0.1"))
        #expect((a * 3).amount == d("0.3"))
        #expect((-a).amount == d("-0.1"))
        var total = Money.zero(.eur)
        total += a
        total += b
        total -= a
        #expect(total.amount == d("0.2"))
        #expect(Money.sum([a, b, b], in: .eur).amount == d("0.5"))
        #expect(Money.sum([], in: .czk) == Money.zero(.czk))
        #expect(Money(d("19.99"), .eur) * 3 == Money(d("59.97"), .eur))
        #expect((Money(1, .eur) * d("0.21")).amount == d("0.21"))
        #expect((Money(d("0.35"), .eur) * d("0.21")).amount == d("0.0735"))
    }

    @Test func flagsAndDescription() {
        #expect(Money.zero(.eur).isZero)
        #expect(Money(-1, .eur).isNegative)
        #expect(!Money(1, .eur).isNegative)
        #expect(Money(d("123.45"), .eur).description == "123.45 EUR")
        #expect(Money(100, .czk).description == "100.00 CZK")
        #expect(Money(d("2.345"), .eur).description == "2.35 EUR")
    }

    @Test func codableUsesPlainStrings() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Money(d("123.45"), .eur))
        #expect(String(decoding: data, as: UTF8.self) == #"{"amount":"123.45","currency":"EUR"}"#)
        let decoded = try JSONDecoder().decode(Money.self, from: data)
        #expect(decoded == Money(d("123.45"), .eur))
        #expect(decoded.currency.minorUnits == 2)
        let yen = try JSONDecoder().decode(Money.self, from: Data(#"{"amount":"1000","currency":"JPY"}"#.utf8))
        #expect(yen.currency.minorUnits == 0)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Money.self, from: Data(#"{"amount":"abc","currency":"EUR"}"#.utf8))
        }
    }

    @Test func currencyCodesAreUppercased() {
        #expect(Currency(code: "eur") == .eur)
        #expect(Currency.known("czk") == .czk)
        #expect(Currency.known("HUF").minorUnits == 2)
        #expect(Currency.known("ISK").minorUnits == 0)
        #expect(Currency.eur.description == "EUR")
    }
}
