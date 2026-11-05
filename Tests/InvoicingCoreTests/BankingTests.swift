import Foundation
import Testing
@testable import InvoicingCore

@Suite struct CzechBankAccountTests {
    @Test func parsesAndValidates() throws {
        let account = try #require(CzechBankAccount(parsing: "19-2000145399/0800"))
        #expect(account.prefix == "19")
        #expect(account.number == "2000145399")
        #expect(account.bankCode == "0800")
        #expect(account.paddedPrefix == "000019")
        #expect(account.paddedNumber == "2000145399")
        #expect(account.description == "19-2000145399/0800")
        let plain = try #require(CzechBankAccount(parsing: "1265098001/5500"))
        #expect(plain.prefix == "")
        #expect(plain.paddedPrefix == "000000")
        #expect(plain.description == "1265098001/5500")
        #expect(CzechBankAccount(parsing: " 000019-2000145399/0800 ")?.description == "19-2000145399/0800")
        #expect(CzechBankAccount(prefix: "123", number: "1265098001", bankCode: "5500") != nil)
        #expect(CzechBankAccount(prefix: "000123", number: "0001265098001", bankCode: "5500")?.description == "123-1265098001/5500")
        // An all-zero prefix (as it comes out of an IBAN) is no prefix at all.
        #expect(CzechBankAccount(parsing: "000000-1265098001/5500")?.description == "1265098001/5500")
        #expect(CzechBankAccount(prefix: "000000", number: "1265098001", bankCode: "5500")?.prefix == "")
    }

    @Test func rejectsBadChecksumsAndShapes() {
        #expect(CzechBankAccount(parsing: "19-2000145398/0800") == nil)   // number checksum
        #expect(CzechBankAccount(parsing: "18-2000145399/0800") == nil)   // prefix checksum
        #expect(CzechBankAccount(parsing: "2000145399/080") == nil)
        #expect(CzechBankAccount(parsing: "2000145399/08000") == nil)
        #expect(CzechBankAccount(parsing: "2000145399/08a0") == nil)
        #expect(CzechBankAccount(parsing: "2000145399") == nil)
        #expect(CzechBankAccount(parsing: "1-2-3/0800") == nil)
        #expect(CzechBankAccount(parsing: "12345678901/0800") == nil)
        #expect(CzechBankAccount(parsing: "abc/0800") == nil)
        #expect(CzechBankAccount(parsing: "/0800") == nil)
        #expect(CzechBankAccount(parsing: "0000000000/5500") == nil)   // an all-zero number
        #expect(CzechBankAccount(parsing: "1234567-2000145399/0800") == nil)
    }

    @Test func codable() throws {
        let account = try #require(CzechBankAccount(parsing: "19-2000145399/0800"))
        let data = try JSONEncoder().encode(account)
        let back = try JSONDecoder().decode(CzechBankAccount.self, from: data)
        #expect(back == account)
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {   // number checksum
            try decoder.decode(CzechBankAccount.self, from: Data(#"{"prefix":"19","number":"2000145398","bankCode":"0800"}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(CzechBankAccount.self, from: Data(#"{"prefix":"","number":"1234567890","bankCode":"0800"}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(CzechBankAccount.self, from: Data(#"{"prefix":"","number":"2000145399","bankCode":"080"}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(CzechBankAccount.self, from: Data(#"{"prefix":"1a","number":"2000145399","bankCode":"0800"}"#.utf8))
        }
        let padded = try decoder.decode(CzechBankAccount.self, from: Data(#"{"prefix":"000019","number":"2000145399","bankCode":"0800"}"#.utf8))
        #expect(padded == account)
        #expect(padded.description == "19-2000145399/0800")
        let noPrefix = try decoder.decode(CzechBankAccount.self, from: Data(#"{"number":"1265098001","bankCode":"5500"}"#.utf8))
        #expect(noPrefix.description == "1265098001/5500")
    }
}

@Suite struct IBANTests {
    @Test func validatesCheckDigits() {
        #expect(IBAN("CZ6508000000192000145399") != nil)
        #expect(IBAN("CZ65 0800 0000 1920 0014 5399") != nil)
        #expect(IBAN("cz65 0800 0000 1920 0014 5399")?.value == "CZ6508000000192000145399")
        #expect(IBAN("GB82 WEST 1234 5698 7654 32") != nil)
        #expect(IBAN("CZ6408000000192000145399") == nil)
        #expect(IBAN("CZ65080000001920001453990") == nil)
        #expect(IBAN("CZ65") == nil)
        #expect(IBAN("6508000000192000145399CZ") == nil)
        #expect(IBAN("CZ65-0800-0000-1920-0014-5399") == nil)
        #expect(IBAN("") == nil)
    }

    @Test func partsAndFormatting() throws {
        let iban = try #require(IBAN("CZ6508000000192000145399"))
        #expect(iban.countryCode == "CZ")
        #expect(iban.checkDigits == "65")
        #expect(iban.bban == "08000000192000145399")
        #expect(iban.formatted == "CZ65 0800 0000 1920 0014 5399")
        #expect(iban.description == "CZ6508000000192000145399")
        #expect(IBAN("GB82WEST12345698765432")?.formatted == "GB82 WEST 1234 5698 7654 32")
    }

    @Test func czechConversionBothWays() throws {
        let account = try #require(CzechBankAccount(parsing: "19-2000145399/0800"))
        let iban = try #require(IBAN.czech(account))
        #expect(iban.value == "CZ6508000000192000145399")
        #expect(iban.czechAccount == account)
        let rb = try #require(CzechBankAccount(parsing: "1265098001/5500"))
        #expect(IBAN.czech(rb)?.value == "CZ5855000000001265098001")
        #expect(IBAN("CZ5855000000001265098001")?.czechAccount == rb)
        let withPrefix = try #require(CzechBankAccount(parsing: "123-1265098001/5500"))
        #expect(IBAN.czech(withPrefix)?.value == "CZ9555000001231265098001")
        #expect(IBAN("CZ9555000001231265098001")?.czechAccount?.description == "123-1265098001/5500")
        #expect(IBAN("GB82WEST12345698765432")?.czechAccount == nil)
    }

    @Test func mod97() {
        #expect(IBAN.mod97("GB82WEST12345698765432") == 1)
        #expect(IBAN.mod97("CZ6508000000192000145399") == 1)
        #expect(IBAN.mod97("CZ0008000000192000145399") == 98 - 65)
    }

    @Test func codable() throws {
        let iban = try #require(IBAN("CZ6508000000192000145399"))
        let data = try JSONEncoder().encode([iban])
        #expect(String(decoding: data, as: UTF8.self) == #"["CZ6508000000192000145399"]"#)
        let back = try JSONDecoder().decode([IBAN].self, from: data)
        #expect(back == [iban])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([IBAN].self, from: Data(#"["CZ64"]"#.utf8)) }
    }
}

@Suite struct PaymentSymbolTests {
    @Test func validation() {
        #expect(PaymentSymbol.variable("2026001")?.digits == "2026001")
        #expect(PaymentSymbol.variable(" 0012 ")?.digits == "0012")
        #expect(PaymentSymbol.variable("0012")?.canonical == "12")
        #expect(PaymentSymbol.constant("0000")?.canonical == "0")
        #expect(PaymentSymbol.specific("1234567890") != nil)
        #expect(PaymentSymbol.specific("12345678901") == nil)
        #expect(PaymentSymbol.variable("12a") == nil)
        #expect(PaymentSymbol.variable("") == nil)
        #expect(PaymentSymbol.variable("１２") == nil)   // full-width digits are not ASCII
        #expect(PaymentSymbol.constant("0308")?.kind == .constant)
    }

    @Test func fromDocumentNumber() {
        #expect(PaymentSymbol.variable(fromDocumentNumber: "FV-2026-001")?.digits == "2026001")
        #expect(PaymentSymbol.variable(fromDocumentNumber: "20260000001234")?.digits == "0000001234")
        #expect(PaymentSymbol.variable(fromDocumentNumber: "20260000001234")?.canonical == "1234")
        #expect(PaymentSymbol.variable(fromDocumentNumber: "ABC") == nil)
        #expect(PaymentSymbol.variable(fromDocumentNumber: "2026001")?.description == "2026001")
        #expect(PaymentSymbol.variable(fromDocumentNumber: "2026001")?.kind == .variable)
    }

    @Test func fromDocumentNumberWithSeriesPrefix() {
        // Invoices and advance requests with the same template get different symbols (ADR 0003 addendum).
        #expect(PaymentSymbol.variable(fromDocumentNumber: "FV-2026-003", prefix: "1")?.digits == "12026003")
        #expect(PaymentSymbol.variable(fromDocumentNumber: "ZF-2026-003", prefix: "2")?.digits == "22026003")
        // The prefix stays, the number loses its leading digits when the symbol would exceed 10 digits.
        #expect(PaymentSymbol.variable(fromDocumentNumber: "20260000001234", prefix: "12")?.digits == "1200001234")
        #expect(PaymentSymbol.variable(fromDocumentNumber: "FV-2026-003", prefix: nil)?.digits == "2026003")
        #expect(PaymentSymbol.variable(fromDocumentNumber: "FV-2026-003", prefix: " ")?.digits == "2026003")
        #expect(PaymentSymbol.variable(fromDocumentNumber: "FV-2026-003", prefix: "A") == nil)
        #expect(PaymentSymbol.variable(fromDocumentNumber: "FV-2026-003", prefix: "1234567890") == nil)
        #expect(PaymentSymbol.variable(fromDocumentNumber: "ABC", prefix: "1") == nil)
    }

    @Test func codable() throws {
        let symbol = try #require(PaymentSymbol.variable("2026001"))
        let data = try JSONEncoder().encode(symbol)
        let back = try JSONDecoder().decode(PaymentSymbol.self, from: data)
        #expect(back == symbol)
        for digits in ["12a", "12345678901", "", "１２"] {
            let json = #"{"kind":"variable","digits":""# + digits + #""}"#
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(PaymentSymbol.self, from: Data(json.utf8)) }
        }
        let leadingZeros = try JSONDecoder().decode(PaymentSymbol.self, from: Data(#"{"kind":"variable","digits":"0012"}"#.utf8))
        #expect(leadingZeros == PaymentSymbol.variable("0012"))
    }
}
