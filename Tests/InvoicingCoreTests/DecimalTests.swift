import Foundation
import Testing
@testable import InvoicingCore

@Suite struct DecimalHelperTests {
    @Test func roundsHalfAwayFromZeroByDefault() {
        #expect(d("2.345").rounded(scale: 2) == d("2.35"))
        #expect(d("-2.345").rounded(scale: 2) == d("-2.35"))
        #expect(d("2.344").rounded(scale: 2) == d("2.34"))
        #expect(d("0.005").rounded(scale: 2) == d("0.01"))
        #expect(d("2.5").rounded(scale: 0) == 3)
        #expect(d("-2.5").rounded(scale: 0) == -3)
        #expect(d("2.345").rounded(scale: 2, mode: .bankers) == d("2.34"))
        #expect(d("2.355").rounded(scale: 2, mode: .bankers) == d("2.36"))
        #expect(d("2.349").rounded(scale: 2, mode: .down) == d("2.34"))
        #expect(d("2.341").rounded(scale: 2, mode: .up) == d("2.35"))
    }

    @Test func parsesLeniently() {
        #expect(Decimal(lenient: "24,310") == d("24.31"))
        #expect(Decimal(lenient: "24.310") == d("24.31"))
        #expect(Decimal(lenient: "-1 234,5") == d("-1234.5"))
        #expect(Decimal(lenient: "1\u{00A0}234") == 1234)
        #expect(Decimal(lenient: " 7 ") == 7)
        #expect(Decimal(lenient: "0,5") == d("0.5"))
        #expect(Decimal(lenient: "") == nil)
        #expect(Decimal(lenient: "abc") == nil)
        #expect(Decimal(lenient: "1,2,3") == nil)
        #expect(Decimal(lenient: "--1") == nil)
        #expect(Decimal(lenient: "1e5") == nil)
        #expect(Decimal(lenient: "-") == nil)
        #expect(Decimal(lenient: ".") == nil)
        #expect(Decimal(lenient: "1 2") == 12)
    }

    @Test func plainStrings() {
        #expect(d("24.31").plainString == "24.31")
        #expect(d("-0.5").plainString == "-0.5")
        #expect(d("100").plainString == "100")
        #expect(d("123456789012.34").plainString == "123456789012.34")
        #expect(d("24.31").plainString(minimumFractionDigits: 3) == "24.310")
        #expect(d("24.3105").plainString(minimumFractionDigits: 3) == "24.3105")
        #expect(d("100").plainString(minimumFractionDigits: 2) == "100.00")
        #expect(d("-7").plainString(minimumFractionDigits: 2) == "-7.00")
        #expect(d("1.5").plainString(minimumFractionDigits: 0) == "1.5")
        #expect(d("0").plainString(minimumFractionDigits: 2) == "0.00")
    }

    @Test func fitsScale() {
        #expect(d("1.25").fits(scale: 2))
        #expect(!d("1.255").fits(scale: 2))
        #expect(d("3").fits(scale: 0))
    }
}
