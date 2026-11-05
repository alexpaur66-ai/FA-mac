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
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CreditorReference.self, from: Data(#""RF00"#.utf8)) }
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

    @Test func payloadByteLimit() throws {
        // Two-byte characters: 70 + 140 of them already exceed 331 bytes although every element is within its length.
        let code = SEPAQRCode(name: String(repeating: "ž", count: 70), iban: try iban("CZ6508000000192000145399"), remittanceText: String(repeating: "ž", count: 140))
        // "BCD\n002\n1\nSCT\n\n" (15 bytes) + name 140 + LF + IBAN 24 + four LFs (after IBAN, amount, purpose, reference) + remittance 280.
        #expect(throws: SEPAQRCode.EncodingError.payloadTooLarge(bytes: 15 + 140 + 1 + 24 + 4 + 280, maximum: 331)) { try code.encoded() }
    }
}
