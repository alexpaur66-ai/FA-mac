import Foundation
import Testing
@testable import InvoicingCore

@Suite struct CreditorReferenceTests {
    @Test func validatesKnownReference() throws {
        // The ISO 11649 example reference.
        let reference = try #require(CreditorReference("RF18 5390 0754 7034"))
        #expect(reference.value == "RF18539007547034")
        #expect(reference.reference == "539007547034")
        #expect(reference.formatted == "RF18 5390 0754 7034")
        #expect(reference.description == "RF18539007547034")
        #expect(CreditorReference("rf18539007547034")?.value == "RF18539007547034")
        #expect(CreditorReference("RF19539007547034") == nil)   // wrong check digits
        #expect(CreditorReference("XX18539007547034") == nil)
        #expect(CreditorReference("RF18") == nil)
        #expect(CreditorReference("RF18-5390") == nil)
        #expect(CreditorReference("RF40123456789012345678901X") == nil)   // 26 characters
    }

    @Test func checkDigitsAreTwoDigitsInTwoToNinetyEight() {
        // Each of these satisfies mod 97 == 1, but 98 − (n mod 97) never yields 00, 01 or 99, and
        // the check digits are never letters.
        #expect(CreditorReference("RF0154") == nil)        // 01 aliases the correct RF9854
        #expect(CreditorReference("RF0072") == nil)        // 00 aliases the correct RF9772
        #expect(CreditorReference("RF9936") == nil)        // 99 aliases the correct RF0236
        #expect(CreditorReference("RFA62026001") == nil)   // letter in a check-digit position
        #expect(CreditorReference("RF9854")?.value == "RF9854")
        #expect(CreditorReference("RF9772")?.value == "RF9772")
        #expect(CreditorReference("RF0236")?.value == "RF0236")
        #expect(CreditorReference("RF602026001")?.value == "RF602026001")
        #expect(CreditorReference("RF18539007547034")?.value == "RF18539007547034")
    }

    @Test func buildsReferencesWithCheckDigits() {
        #expect(CreditorReference(reference: "539007547034")?.value == "RF18539007547034")
        #expect(CreditorReference(reference: "2026001")?.value == "RF602026001")
        #expect(CreditorReference(reference: "fv2026001")?.value == "RF84FV2026001")
        #expect(CreditorReference(reference: "1")?.value == "RF741")
        #expect(CreditorReference(reference: "123456789012345678901")?.value == "RF40123456789012345678901")
        #expect(CreditorReference(reference: "1234567890123456789012") == nil)   // 22 characters
        #expect(CreditorReference(reference: "") == nil)
        #expect(CreditorReference(reference: "2026-001") == nil)
        // Every built reference validates.
        for text in ["A", "ZZ99", "2026001", "INV00000000000000001"] {
            let built = CreditorReference(reference: text)
            #expect(built != nil)
            #expect(built.flatMap { CreditorReference($0.value) } == built)
        }
    }

    @Test func codable() throws {
        let reference = try #require(CreditorReference(reference: "2026001"))
        let data = try JSONEncoder().encode(reference)
        #expect(String(decoding: data, as: UTF8.self) == #""RF602026001""#)
        let back = try JSONDecoder().decode(CreditorReference.self, from: data)
        #expect(back == reference)
        let valid = try JSONDecoder().decode(CreditorReference.self, from: Data(#""RF18539007547034""#.utf8))
        #expect(valid.value == "RF18539007547034")
        // Well-formed JSON strings that fail only the ISO 11649 validation: wrong check digits, no RF
        // prefix, too short. The error must come from CreditorReference, not from the JSON parser.
        for json in [#""RF19539007547034""#, #""XX18539007547034""#, #""RF00""#] {
            do {
                _ = try JSONDecoder().decode(CreditorReference.self, from: Data(json.utf8))
                Issue.record("Decoded an invalid creditor reference from \(json)")
            } catch DecodingError.dataCorrupted(let context) {
                #expect(context.debugDescription.hasPrefix("Invalid creditor reference"))
            } catch {
                Issue.record("Unexpected error for \(json): \(error)")
            }
        }
    }
}

@Suite struct SEPAQRCodeTests {
    func iban(_ text: String) throws -> IBAN { try #require(IBAN(text)) }

    @Test func encodesAnInvoicePayment() throws {
        let code = SEPAQRCode(
            name: "Nováková a synové s. r. o.",
            iban: try iban("CZ5855000000001265098001"),
            amount: d("480.5"),
            remittanceText: "FV-2026-001"
        )
        let payload = try code.encoded()
        #expect(payload == "BCD\n002\n1\nSCT\n\nNováková a synové s. r. o.\nCZ5855000000001265098001\nEUR480.50\n\n\nFV-2026-001")
        #expect(payload.utf8.count == 93)
        #expect(!payload.hasSuffix("\n"))
        #expect(payload.split(separator: "\n", omittingEmptySubsequences: false).count == 11)
    }

    @Test func minimalPayloadEndsWithTheIBAN() throws {
        let code = SEPAQRCode(name: "Firma", iban: try iban("CZ6508000000192000145399"))
        let payload = try code.encoded()
        #expect(payload == "BCD\n002\n1\nSCT\n\nFirma\nCZ6508000000192000145399")
    }

    @Test func version001RequiresBIC() throws {
        var code = SEPAQRCode(version: .v001, name: "Firma", iban: try iban("CZ6508000000192000145399"), amount: 1)
        #expect(throws: SEPAQRCode.EncodingError.bicRequired) { try code.encoded() }
        code.bic = BIC("RZBCCZPP")
        let payload = try code.encoded()
        #expect(payload == "BCD\n001\n1\nSCT\nRZBCCZPP\nFirma\nCZ6508000000192000145399\nEUR1.00")
    }

    @Test func structuredReferenceAndInformation() throws {
        var code = SEPAQRCode(name: "Firma", iban: try iban("CZ6508000000192000145399"), amount: d("1234.5"), purpose: "scve")
        code.creditorReference = CreditorReference(reference: "2026001")
        code.information = "Faktura 2026001, splatnost 20. 11. 2026"
        let payload = try code.encoded()
        #expect(payload == "BCD\n002\n1\nSCT\n\nFirma\nCZ6508000000192000145399\nEUR1234.50\nSCVE\nRF602026001\n\nFaktura 2026001, splatnost 20. 11. 2026")
        code.remittanceText = "also text"
        #expect(throws: SEPAQRCode.EncodingError.bothRemittanceForms) { try code.encoded() }
    }

    @Test func blankRemittanceTextDoesNotConflictWithAReference() throws {
        let account = try iban("CZ6508000000192000145399")
        let reference = CreditorReference(reference: "2026001")
        for text in ["", "  ", " \n "] {
            let payload = try SEPAQRCode(name: "Firma", iban: account, creditorReference: reference, remittanceText: text).encoded()
            #expect(payload == "BCD\n002\n1\nSCT\n\nFirma\nCZ6508000000192000145399\n\n\nRF602026001")
        }
    }

    @Test func amountLimits() throws {
        let account = try iban("CZ6508000000192000145399")
        let smallest = try SEPAQRCode(name: "F", iban: account, amount: d("0.01")).encoded()
        let largest = try SEPAQRCode(name: "F", iban: account, amount: d("999999999.99")).encoded()
        #expect(smallest.hasSuffix("\nEUR0.01"))
        #expect(largest.hasSuffix("\nEUR999999999.99"))
        #expect(throws: SEPAQRCode.EncodingError.invalidAmount(0)) { try SEPAQRCode(name: "F", iban: account, amount: 0).encoded() }
        #expect(throws: SEPAQRCode.EncodingError.invalidAmount(d("0.005"))) { try SEPAQRCode(name: "F", iban: account, amount: d("0.005")).encoded() }
        #expect(throws: SEPAQRCode.EncodingError.invalidAmount(1_000_000_000)) { try SEPAQRCode(name: "F", iban: account, amount: 1_000_000_000).encoded() }
        #expect(throws: SEPAQRCode.EncodingError.invalidAmount(d("1.005"))) { try SEPAQRCode(name: "F", iban: account, amount: d("1.005")).encoded() }
    }

    @Test func textRules() throws {
        let account = try iban("CZ6508000000192000145399")
        #expect(throws: SEPAQRCode.EncodingError.emptyName) { try SEPAQRCode(name: "  \n ", iban: account).encoded() }
        #expect(throws: SEPAQRCode.EncodingError.tooLong(element: "Name", maximum: 70, actual: 71)) {
            try SEPAQRCode(name: String(repeating: "N", count: 71), iban: account).encoded()
        }
        #expect(throws: SEPAQRCode.EncodingError.tooLong(element: "Remittance Information (Unstructured)", maximum: 140, actual: 141)) {
            try SEPAQRCode(name: "F", iban: account, remittanceText: String(repeating: "R", count: 141)).encoded()
        }
        #expect(throws: SEPAQRCode.EncodingError.tooLong(element: "Beneficiary to Originator information", maximum: 70, actual: 71)) {
            try SEPAQRCode(name: "F", iban: account, information: String(repeating: "I", count: 71)).encoded()
        }
        #expect(throws: SEPAQRCode.EncodingError.invalidPurpose("GDDSX")) { try SEPAQRCode(name: "F", iban: account, purpose: "GDDSX").encoded() }
        #expect(throws: SEPAQRCode.EncodingError.invalidPurpose("GD-S")) { try SEPAQRCode(name: "F", iban: account, purpose: "GD-S").encoded() }
        // Line breaks inside a value would break the element structure; they become spaces.
        let payload = try SEPAQRCode(name: "Firma\ns. r. o.", iban: account, remittanceText: "řádek 1\r\nřádek 2").encoded()
        #expect(payload.split(separator: "\n", omittingEmptySubsequences: false).count == 11)
        #expect(payload.contains("\nFirma s. r. o.\n"))
        #expect(payload.hasSuffix("\nřádek 1 řádek 2"))
    }

    @Test func decomposedTextIsNormalisedAndCountedInCodePoints() throws {
        let account = try iban("CZ6508000000192000145399")
        // 70 × "e" + U+0301 (decomposed é): NFC turns it into 70 × U+00E9, 70 code points and 140 bytes.
        let decomposed = String(repeating: "e\u{301}", count: 70)
        let payload = try SEPAQRCode(name: decomposed, iban: account).encoded()
        let lines = payload.split(separator: "\n", omittingEmptySubsequences: false)
        let nameLine = try #require(lines.count > 5 ? String(lines[5]) : nil)
        #expect(nameLine == String(repeating: "\u{E9}", count: 70))
        #expect(nameLine.unicodeScalars.count == 70)
        #expect(nameLine.utf8.count == 140)
        #expect(throws: SEPAQRCode.EncodingError.tooLong(element: "Name", maximum: 70, actual: 71)) {
            try SEPAQRCode(name: String(repeating: "e\u{301}", count: 71), iban: account).encoded()
        }
        // "q" + U+0301 has no precomposed form: 70 grapheme clusters but 140 code points for the bank.
        #expect(throws: SEPAQRCode.EncodingError.tooLong(element: "Name", maximum: 70, actual: 140)) {
            try SEPAQRCode(name: String(repeating: "q\u{301}", count: 70), iban: account).encoded()
        }
        let remittance = try SEPAQRCode(name: "F", iban: account, remittanceText: String(repeating: "e\u{301}", count: 140)).encoded()
        #expect(remittance.hasSuffix("\n" + String(repeating: "\u{E9}", count: 140)))
        let information = try SEPAQRCode(name: "F", iban: account, information: String(repeating: "e\u{301}", count: 70)).encoded()
        #expect(information.hasSuffix("\n" + String(repeating: "\u{E9}", count: 70)))
    }

    @Test func payloadByteLimit() throws {
        // Two-byte characters: 70 + 140 of them already exceed 331 bytes although every element is within its length.
        let code = SEPAQRCode(name: String(repeating: "ž", count: 70), iban: try iban("CZ6508000000192000145399"), remittanceText: String(repeating: "ž", count: 140))
        // "BCD\n002\n1\nSCT\n\n" (15 bytes) + name 140 + LF + IBAN 24 + four LFs (after IBAN, amount, purpose, reference) + remittance 280.
        #expect(throws: SEPAQRCode.EncodingError.payloadTooLarge(bytes: 15 + 140 + 1 + 24 + 4 + 280, maximum: 331)) { try code.encoded() }
    }
}
