import Foundation
import Testing
@testable import InvoicingCore

@Suite struct DecimalInputTests {
    let cs = Locale(identifier: "cs_CZ")
    let us = Locale(identifier: "en_US")

    @Test func czechNotation() {
        #expect(DecimalInput.parse("1 234,50", locale: cs) == d("1234.5"))
        #expect(DecimalInput.parse("1\u{a0}234,50", locale: cs) == d("1234.5"))
        #expect(DecimalInput.parse("1234,5", locale: cs) == d("1234.5"))
        #expect(DecimalInput.parse("1234.50", locale: cs) == d("1234.5"))
        #expect(DecimalInput.parse("24,315", locale: cs) == d("24.315"))
        #expect(DecimalInput.parse("1.234,50", locale: cs) == d("1234.5"))
        #expect(DecimalInput.parse("1,234.50", locale: cs) == d("1234.5"))
    }

    @Test func englishNotation() {
        #expect(DecimalInput.parse("36,5", locale: us) == d("36.5"))
        #expect(DecimalInput.parse("24,315", locale: us) == d("24315"))
        #expect(DecimalInput.parse("1,234.50", locale: us) == d("1234.5"))
        #expect(DecimalInput.parse("1.234,50", locale: us) == d("1234.5"))
        #expect(DecimalInput.parse("1,234,567", locale: us) == d("1234567"))
        #expect(DecimalInput.parse("1234,50", locale: us) == d("1234.5"))
    }

    @Test func signsAndFractions() {
        #expect(DecimalInput.parse("-5", locale: cs) == d("-5"))
        #expect(DecimalInput.parse("\u{2212}5", locale: cs) == d("-5"))
        #expect(DecimalInput.parse(".5", locale: us) == d("0.5"))
        #expect(DecimalInput.parse("0", locale: cs) == 0)
        #expect(DecimalInput.parse("12", locale: us) == 12)
    }

    @Test func rejectsTypos() {
        for text in ["1.5.", "1o0", "1,23,4", "", " ", "-", "1,234.5,6", "1,23.5", "abc", "1..5", "1,,5", "--5", "5-"] {
            #expect(DecimalInput.parse(text, locale: us) == nil, "\(text)")
            #expect(DecimalInput.parse(text, locale: cs) == nil, "\(text)")
        }
    }

    @Test func ratesAreNeverGrouped() {
        #expect(DecimalInput.parseRate("24,315") == d("24.315"))
        #expect(DecimalInput.parseRate("24.315") == d("24.315"))
        #expect(DecimalInput.parseRate(" 24,315\n") == d("24.315"))
        #expect(DecimalInput.parseRate("1,234.5") == nil)
        #expect(DecimalInput.parseRate("1 234") == nil)
        #expect(DecimalInput.parseRate("24 315") == nil)
        #expect(DecimalInput.parseRate("") == nil)
        #expect(DecimalInput.parseRate("24,3x") == nil)
    }

    @Test func ratesArePositive() {
        for text in ["0", "0,000", "-24,315", "\u{2212}5", "-0"] {
            #expect(DecimalInput.parseRate(text) == nil, "\(text)")
        }
        #expect(DecimalInput.parseRate("0,001") == d("0.001"))
    }

    @Test func percentsAcceptZero() {
        #expect(DecimalInput.parsePercent("0") == 0)
        #expect(DecimalInput.parsePercent("21") == 21)
        #expect(DecimalInput.parsePercent("12,0") == 12)
        #expect(DecimalInput.parsePercent(" 21 ") == 21)
        #expect(DecimalInput.parsePercent("2 1") == nil)
        #expect(DecimalInput.parsePercent("1,2,3") == nil)
    }
}
