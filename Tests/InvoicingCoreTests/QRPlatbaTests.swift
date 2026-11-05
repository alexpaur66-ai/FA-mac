import Foundation
import Testing
@testable import InvoicingCore

@Suite struct BICTests {
    @Test func validatesShape() {
        #expect(BIC("RZBCCZPP")?.value == "RZBCCZPP")
        #expect(BIC(" rzbcczpp ")?.value == "RZBCCZPP")
        #expect(BIC("RZBCCZPPXXX")?.value == "RZBCCZPPXXX")
        #expect(BIC("RZBCCZPP")?.countryCode == "CZ")
        #expect(BIC("RZBCCZP") == nil)
        #expect(BIC("RZBCCZPPXX") == nil)
        #expect(BIC("1ZBCCZPP") == nil)
        #expect(BIC("RZBC12PP") == nil)
        #expect(BIC("RZBC-ZPP") == nil)
        #expect(BIC("") == nil)
    }

    @Test func codable() throws {
        let bic = try #require(BIC("RZBCCZPP"))
        let data = try JSONEncoder().encode(bic)
        #expect(String(decoding: data, as: UTF8.self) == #""RZBCCZPP""#)
        let back = try JSONDecoder().decode(BIC.self, from: data)
        #expect(back == bic)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(BIC.self, from: Data(#""RZB""#.utf8)) }
    }
}

@Suite struct PaymentStringTextTests {
    @Test func stripsDiacritics() {
        #expect(PaymentStringText.strippingDiacritics("Příliš žluťoučký kůň úpěl ďábelské ódy") == "Prilis zlutoucky kun upel dabelske ody")
        #expect(PaymentStringText.strippingDiacritics("Łódź, Straße, Ørsted, Đakovo") == "Lodz, Strasse, Orsted, Dakovo")
        #expect(PaymentStringText.strippingDiacritics("ASCII only 123") == "ASCII only 123")
        #expect(PaymentStringText.strippingDiacritics("") == "")
    }

    @Test func percentEncodesOutsideTheAllowedSet() {
        let encoded = PaymentStringText.percentEncoding("A*B%C ů€") { $0 != "*" && $0 != "%" && $0.isASCII }
        #expect(encoded == "A%2AB%25C %C5%AF%E2%82%AC")
    }

    @Test func collapsesWhitespace() {
        #expect(PaymentStringText.collapsingWhitespace("  Platba  za\nzboží\t ") == "Platba za zboží")
        #expect(PaymentStringText.collapsingWhitespace("") == "")
        #expect(PaymentStringText.collapsingWhitespace("   ") == "")
    }
}

@Suite struct QRPlatbaTests {
    // Example string published in the QR platba specification (qr-platba.cz, read 5 Nov 2026).
    let specExample = "SPD*1.0*ACC:CZ9106000000000000000123*AM:450.00*CC:CZK*MSG:PLATBA ZA ZBOZI*X-VS:1234567890"

    func iban(_ text: String) throws -> IBAN { try #require(IBAN(text)) }

    @Test func encodesTheSpecificationExample() throws {
        let payment = QRPlatba(
            iban: try iban("CZ9106000000000000000123"),
            amount: 450,
            currency: .czk,
            variableSymbol: PaymentSymbol.variable("1234567890"),
            message: "Platba za zboží"
        )
        let encoded = try payment.encoded()
        #expect(encoded == specExample)
    }

    @Test func accountWithBICAndAllFields() throws {
        var payment = QRPlatba(iban: try iban("CZ5855000000001265098001"), bic: BIC("RZBCCZPP"))
        payment.amount = d("480.5")
        payment.currency = .eur
        payment.dueDate = day("2026-12-31")
        payment.variableSymbol = PaymentSymbol.variable("2026001")
        payment.specificSymbol = PaymentSymbol.specific("0012")
        payment.constantSymbol = PaymentSymbol.constant("0308")
        payment.message = "Faktura FV-2026-001"
        payment.recipientName = "Žluťoučký s.r.o."
        payment.paymentReference = "1234567890123456"
        payment.paymentType = "ip"
        let encoded = try payment.encoded()
        #expect(encoded == "SPD*1.0*ACC:CZ5855000000001265098001+RZBCCZPP*AM:480.50*CC:EUR*RF:1234567890123456*RN:ZLUTOUCKY S.R.O.*DT:20261231*PT:IP*MSG:FAKTURA FV-2026-001*X-VS:2026001*X-SS:0012*X-KS:0308")
    }

    @Test func minimalStringIsJustTheAccount() throws {
        let payment = QRPlatba(iban: try iban("CZ6508000000192000145399"))
        let encoded = try payment.encoded()
        #expect(encoded == "SPD*1.0*ACC:CZ6508000000192000145399")
    }

    @Test func textIsFoldedCollapsedAndEscaped() throws {
        var payment = QRPlatba(iban: try iban("CZ6508000000192000145399"), message: "  Příliš  žluťoučký\nkůň 100%*  ")
        var encoded = try payment.encoded()
        #expect(encoded.hasSuffix("*MSG:PRILIS ZLUTOUCKY KUN 100%25%2A"))

        payment.foldsTextToQRAlphanumeric = false
        payment.message = "Faktura č. 5 za café"
        encoded = try payment.encoded()
        // č (U+010D) is outside ISO-8859-1 and gets percent-encoded as UTF-8; é (U+00E9) is inside and stays.
        #expect(encoded.hasSuffix("*MSG:Faktura %C4%8D. 5 za café"))
    }

    @Test func amountFormatting() throws {
        let account = try iban("CZ6508000000192000145399")
        let smallest = try QRPlatba(iban: account, amount: d("0.01")).encoded()
        let padded = try QRPlatba(iban: account, amount: d("1234567.8")).encoded()
        let largest = try QRPlatba(iban: account, amount: QRPlatba.maximumAmount).encoded()
        #expect(smallest.hasSuffix("*AM:0.01"))
        #expect(padded.hasSuffix("*AM:1234567.80"))
        #expect(largest.hasSuffix("*AM:9999999.99"))
        #expect(throws: QRPlatba.EncodingError.invalidAmount(0)) { try QRPlatba(iban: account, amount: 0).encoded() }
        #expect(throws: QRPlatba.EncodingError.invalidAmount(-1)) { try QRPlatba(iban: account, amount: -1).encoded() }
        #expect(throws: QRPlatba.EncodingError.invalidAmount(d("1.005"))) { try QRPlatba(iban: account, amount: d("1.005")).encoded() }
        #expect(throws: QRPlatba.EncodingError.invalidAmount(10_000_000)) { try QRPlatba(iban: account, amount: 10_000_000).encoded() }
    }

    @Test func rejectsOverlongAndMalformedValues() throws {
        let account = try iban("CZ6508000000192000145399")
        let longMessage = String(repeating: "A", count: 61)
        #expect(throws: QRPlatba.EncodingError.tooLong(key: "MSG", maximum: 60, actual: 61)) {
            try QRPlatba(iban: account, message: longMessage).encoded()
        }
        // Percent-encoding counts towards the limit: 59 letters + "*" (3 characters) = 62.
        #expect(throws: QRPlatba.EncodingError.tooLong(key: "MSG", maximum: 60, actual: 62)) {
            try QRPlatba(iban: account, message: String(repeating: "A", count: 59) + "*").encoded()
        }
        #expect(throws: QRPlatba.EncodingError.tooLong(key: "RN", maximum: 35, actual: 36)) {
            try QRPlatba(iban: account, recipientName: String(repeating: "B", count: 36)).encoded()
        }
        #expect(throws: QRPlatba.EncodingError.invalidPaymentReference("12a")) {
            try QRPlatba(iban: account, paymentReference: "12a").encoded()
        }
        #expect(throws: QRPlatba.EncodingError.invalidPaymentReference("12345678901234567")) {
            try QRPlatba(iban: account, paymentReference: "12345678901234567").encoded()
        }
        #expect(throws: QRPlatba.EncodingError.invalidPaymentType("INST")) {
            try QRPlatba(iban: account, paymentType: "INST").encoded()
        }
        #expect(throws: QRPlatba.EncodingError.invalidPaymentType("")) {
            try QRPlatba(iban: account, paymentType: "").encoded()
        }
    }

    @Test func currencyMustBeThreeLetters() throws {
        let account = try iban("CZ9106000000000000000123")
        // "*" is the field separator: "CC:E*R" would split into CC:E and a stray field R.
        #expect(throws: QRPlatba.EncodingError.invalidCurrency("E*R")) {
            try QRPlatba(iban: account, amount: 450, currency: Currency(code: "E*R")).encoded()
        }
        #expect(throws: QRPlatba.EncodingError.invalidCurrency("")) {
            try QRPlatba(iban: account, currency: Currency(code: "")).encoded()
        }
        #expect(throws: QRPlatba.EncodingError.invalidCurrency("12")) {
            try QRPlatba(iban: account, currency: Currency(code: "12")).encoded()
        }
        #expect(throws: QRPlatba.EncodingError.invalidCurrency("EU ")) {
            try QRPlatba(iban: account, currency: Currency(code: "EU ")).encoded()
        }
        #expect(throws: QRPlatba.EncodingError.invalidCurrency("EURO")) {
            try QRPlatba(iban: account, currency: Currency(code: "EURO")).encoded()
        }
        let czk = try QRPlatba(iban: account, currency: .czk).encoded()
        let eur = try QRPlatba(iban: account, currency: Currency(code: "eur")).encoded()
        #expect(czk == "SPD*1.0*ACC:CZ9106000000000000000123*CC:CZK")
        #expect(eur == "SPD*1.0*ACC:CZ9106000000000000000123*CC:EUR")
    }

    @Test func blankTextFieldsAreLeftOut() throws {
        let account = try iban("CZ9106000000000000000123")
        let payment = QRPlatba(iban: account, amount: 450, currency: .czk, message: "   ", recipientName: "")
        let encoded = try payment.encoded()
        #expect(encoded == "SPD*1.0*ACC:CZ9106000000000000000123*AM:450.00*CC:CZK")
        #expect(throws: QRPlatba.EncodingError.invalidPaymentType("A%")) {
            try QRPlatba(iban: account, paymentType: "A%").encoded()
        }
    }

    @Test func symbolsKeepTheirDigits() throws {
        let payment = QRPlatba(iban: try iban("CZ6508000000192000145399"), variableSymbol: PaymentSymbol.variable(fromDocumentNumber: "FV-2026-001"))
        let encoded = try payment.encoded()
        #expect(encoded.hasSuffix("*X-VS:2026001"))
        #expect(!encoded.contains("X-SS"))
        #expect(!encoded.contains("X-KS"))
    }

    @Test func everyProducedCharacterIsAllowedByTheFormat() throws {
        var payment = QRPlatba(iban: try iban("CZ5855000000001265098001"), bic: BIC("RZBCCZPP"), amount: d("1.5"), currency: .czk)
        payment.message = "Záloha 50 % na projekt \"Alfa\" & spol. — děkujeme!"
        payment.recipientName = "Nováková & synové, s. r. o."
        let encoded = try payment.encoded()
        let valuePart = encoded.dropFirst(QRPlatba.header.count)
        #expect(valuePart.allSatisfy { $0.isASCII && $0 != "\n" })
        #expect(encoded.components(separatedBy: "*").count == 7)
    }
}
