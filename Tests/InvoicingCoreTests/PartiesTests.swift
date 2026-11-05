import Foundation
import Testing
@testable import InvoicingCore

@Suite struct IdentificationNumberTests {
    @Test func validatesTheCheckDigit() {
        // Checksum-valid examples (the check digit is the weighted remainder rule, recomputed in Python).
        for valid in ["45274649", "48136450", "26168685", "27082440", "00006947", "12345679", "10000071", "10000020"] {
            #expect(IdentificationNumber(valid)?.digits == valid)
        }
        #expect(IdentificationNumber("12345678") == nil)
        #expect(IdentificationNumber("00000000") == nil)
        #expect(IdentificationNumber("6947")?.digits == "00006947")
        #expect(IdentificationNumber("1")?.digits == "00000001")
        #expect(IdentificationNumber("452 746 49")?.digits == "45274649")
        #expect(IdentificationNumber("452746490") == nil)
        #expect(IdentificationNumber("4527464A") == nil)
        #expect(IdentificationNumber("") == nil)
        #expect(IdentificationNumber("４５２７４６４９") == nil)
    }

    @Test func codable() throws {
        let number = try #require(IdentificationNumber("00006947"))
        let data = try JSONEncoder().encode(number)
        #expect(String(decoding: data, as: UTF8.self) == #""00006947""#)
        let back = try JSONDecoder().decode(IdentificationNumber.self, from: data)
        #expect(back == number)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(IdentificationNumber.self, from: Data(#""12345678""#.utf8)) }
    }
}

@Suite struct VATIdentifierTests {
    @Test func parsesCzechAndForeignIdentifiers() throws {
        let czech = try #require(VATIdentifier("CZ45274649"))
        #expect(czech.countryCode == "CZ")
        #expect(czech.number == "45274649")
        #expect(czech.value == "CZ45274649")
        #expect(czech.isCzech)
        #expect(czech.isEU)
        #expect(VATIdentifier("cz 452 746 49")?.value == "CZ45274649")
        #expect(VATIdentifier("CZ12345678") == nil)            // bad IČO check digit
        #expect(VATIdentifier("CZ6812345678")?.number == "6812345678")   // ten digits: natural person
        #expect(VATIdentifier("CZ123456789") != nil)            // nine digits: natural person
        #expect(VATIdentifier("CZ1234567") == nil)
        #expect(VATIdentifier("CZ12345678901") == nil)
        #expect(VATIdentifier("CZ4527464A") == nil)
        let german = try #require(VATIdentifier("DE 123 456 789"))
        #expect(german.value == "DE123456789")
        #expect(german.isEU)
        #expect(!german.isCzech)
        #expect(VATIdentifier("ATU12345678")?.isEU == true)
        #expect(VATIdentifier("EL123456789")?.isEU == true)
        // Greece's ISO code is accepted and stored as the VAT prefix "EL".
        #expect(VATIdentifier("GR123456789")?.value == "EL123456789")
        #expect(VATIdentifier("GR123456789")?.countryCode == "EL")
        #expect(VATIdentifier("GR123456789")?.isEU == true)
        #expect(VATIdentifier("gr 123 456 789") == VATIdentifier("EL123456789"))
        // Non-ASCII characters are rejected, not folded by uppercasing ("ß" -> "SS", "ﬁ" -> "FI").
        #expect(VATIdentifier("ATU1234567ß") == nil)
        #expect(VATIdentifier("DE12345678ﬁ") == nil)
        #expect(VATIdentifier("GB123456789")?.isEU == false)
        #expect(VATIdentifier("CHE-123.456.789")?.value == "CHE123456789")
        #expect(VATIdentifier("XI123456789")?.isEU == false)
        #expect(VATIdentifier("D1234") == nil)
        #expect(VATIdentifier("DE") == nil)
        #expect(VATIdentifier("DE1") == nil)
        #expect(VATIdentifier("DE12*45") == nil)
        #expect(VATIdentifier.euPrefixes.count == 27)
    }

    @Test func fromIdentificationNumber() throws {
        let ico = try #require(IdentificationNumber("45274649"))
        #expect(VATIdentifier(czech: ico).value == "CZ45274649")
        #expect(VATIdentifier(czech: ico) == VATIdentifier("CZ45274649"))
    }

    @Test func codable() throws {
        let identifier = try #require(VATIdentifier("DE123456789"))
        let data = try JSONEncoder().encode(identifier)
        #expect(String(decoding: data, as: UTF8.self) == #""DE123456789""#)
        #expect(try JSONDecoder().decode(VATIdentifier.self, from: data) == identifier)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(VATIdentifier.self, from: Data(#""CZ12345678""#.utf8)) }
        let greek = try JSONDecoder().decode(VATIdentifier.self, from: Data(#""GR123456789""#.utf8))
        #expect(greek.value == "EL123456789")
        #expect(greek.isEU)
    }
}

@Suite struct PostalAddressTests {
    @Test func czechAddressLines() {
        let address = PostalAddress(street: " Dlouhá 12 ", city: "Praha 1", postalCode: "11000", countryCode: "cz")
        #expect(address.countryCode == "CZ")
        #expect(address.isCzech)
        #expect(address.postalCode == "11000")
        #expect(address.formattedPostalCode == "110 00")
        #expect(address.hasValidPostalCode)
        #expect(address.lines() == ["Dlouhá 12", "110 00 Praha 1"])
        #expect(address.lines(countryName: "Česká republika", alwaysIncludeCountry: true) == ["Dlouhá 12", "110 00 Praha 1", "Česká republika"])
        #expect(PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "110 00").postalCode == "11000")
        #expect(!PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "1100").hasValidPostalCode)
        #expect(PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "1100").formattedPostalCode == "1100")
    }

    @Test func foreignAddressLines() {
        let address = PostalAddress(street: "Hauptstraße 5\nHinterhaus", city: "Berlin", postalCode: "10115", countryCode: "DE")
        #expect(!address.isCzech)
        #expect(address.formattedPostalCode == "10115")
        #expect(address.hasValidPostalCode)
        #expect(address.lines() == ["Hauptstraße 5", "Hinterhaus", "10115 Berlin", "DE"])
        #expect(address.lines(countryName: "Germany") == ["Hauptstraße 5", "Hinterhaus", "10115 Berlin", "Germany"])
        let noCode = PostalAddress(street: "1 Main St", city: "Dublin", postalCode: "", countryCode: "IE")
        #expect(!noCode.hasValidPostalCode)
        #expect(noCode.lines() == ["1 Main St", "Dublin", "IE"])
    }

    @Test func codable() throws {
        let address = PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "110 00")
        let data = try JSONEncoder().encode(address)
        #expect(try JSONDecoder().decode(PostalAddress.self, from: data) == address)
    }

    @Test func decodingNormalizes() throws {
        let json = #"{"street":"Dlouhá 12","city":"Praha 1","postalCode":"110 00","countryCode":"cz"}"#
        let address = try JSONDecoder().decode(PostalAddress.self, from: Data(json.utf8))
        #expect(address.countryCode == "CZ")
        #expect(address.postalCode == "11000")
        #expect(address.isCzech)
        #expect(address.lines() == ["Dlouhá 12", "110 00 Praha 1"])
        #expect(address == PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "11000"))
    }

    @Test func splitsStreetOnAnyNewline() {
        let windows = PostalAddress(street: "Dlouhá 12\r\nbudova B", city: "Praha 1", postalCode: "110 00")
        #expect(windows.lines() == ["Dlouhá 12", "budova B", "110 00 Praha 1"])
        let unix = PostalAddress(street: "Dlouhá 12\nbudova B\n", city: "Praha 1", postalCode: "110 00")
        #expect(unix.lines() == ["Dlouhá 12", "budova B", "110 00 Praha 1"])
    }

    @Test func valuesSetThroughSetters() {
        var address = PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "11000")
        address.countryCode = "cz"
        #expect(address.isCzech)
        #expect(address.lines() == ["Dlouhá 12", "110 00 Praha 1"])

        var moved = PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "110 00", countryCode: "DE")
        #expect(moved.postalCode == "110 00")
        moved.countryCode = "CZ"
        #expect(moved.hasValidPostalCode)
        #expect(moved.formattedPostalCode == "110 00")

        var foreign = PostalAddress(street: "Hauptstraße 5", city: "Berlin", postalCode: "10115", countryCode: "DE")
        foreign.countryCode = " de "
        #expect(foreign.lines() == ["Hauptstraße 5", "10115 Berlin", "DE"])
    }
}

@Suite struct RegistryEntryTests {
    @Test func sentences() throws {
        let entry = try #require(RegistryEntry(court: .prague, section: " c ", insert: " 123456 "))
        #expect(entry.section == "C")
        #expect(entry.insert == "123456")
        #expect(entry.sentence(language: .czech) == "Zapsána v obchodním rejstříku vedeném Městským soudem v Praze, oddíl C, vložka 123456.")
        #expect(entry.sentence(language: .english) == "Registered in the Commercial Register kept by the Municipal Court in Prague, Section C, Insert 123456.")
        let brno = try #require(RegistryEntry(court: .brno, section: "C", insert: "99"))
        #expect(brno.sentence(language: .czech) == "Zapsána v obchodním rejstříku vedeném Krajským soudem v Brně, oddíl C, vložka 99.")
        #expect(brno.sentence(language: .english) == "Registered in the Commercial Register kept by the Regional Court in Brno, Section C, Insert 99.")
        #expect(RegistryCourt.allCases.count == 7)
        for court in RegistryCourt.allCases {
            #expect(court.czechNominative.hasPrefix("Městský soud") || court.czechNominative.hasPrefix("Krajský soud"))
            #expect(court.czechInstrumental.hasPrefix("Městským soudem") || court.czechInstrumental.hasPrefix("Krajským soudem"))
            #expect(court.english.contains("Court in "))
        }
    }

    @Test func keepsMixedCaseSectionCodes() throws {
        let cooperative = try #require(RegistryEntry(court: .brno, section: " Dr ", insert: "1234"))
        #expect(cooperative.section == "Dr")
        #expect(cooperative.sentence(language: .czech) == "Zapsána v obchodním rejstříku vedeném Krajským soudem v Brně, oddíl Dr, vložka 1234.")
        #expect(RegistryEntry(court: .brno, section: "dr", insert: "1")?.section == "Dr")
        #expect(RegistryEntry(court: .brno, section: "c", insert: "1")?.section == "C")
        #expect(RegistryEntry(court: .brno, section: "B", insert: "1")?.section == "B")
    }

    @Test func rejectsEmptySectionOrInsert() {
        #expect(RegistryEntry(court: .prague, section: "C", insert: "") == nil)
        #expect(RegistryEntry(court: .prague, section: "C", insert: "   ") == nil)
        #expect(RegistryEntry(court: .prague, section: "", insert: "123456") == nil)
        #expect(RegistryEntry(court: .prague, section: " ", insert: "123456") == nil)
    }

    @Test func codable() throws {
        let entry = try #require(RegistryEntry(court: .ostrava, section: "B", insert: "1"))
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder().decode(RegistryEntry.self, from: data) == entry)
        let empty = #"{"court":"prague","section":"C","insert":""}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegistryEntry.self, from: Data(empty.utf8)) }
        let untrimmed = #"{"court":"prague","section":" c ","insert":" 123456 "}"#
        let decoded = try JSONDecoder().decode(RegistryEntry.self, from: Data(untrimmed.utf8))
        #expect(decoded.section == "C")
        #expect(decoded.insert == "123456")
    }
}

@Suite struct BankConnectionTests {
    @Test func czechAndForeignAccounts() throws {
        let account = try #require(CzechBankAccount(parsing: "1265098001/5500"))
        let connection = try #require(BankConnection(czech: account, bic: BIC("RZBCCZPP"), bankName: "Raiffeisenbank a.s.", currency: .czk))
        #expect(connection.iban.value == "CZ5855000000001265098001")
        #expect(connection.domesticAccount == account)
        #expect(connection.domesticLabel == "1265098001/5500")
        #expect(connection.bic?.value == "RZBCCZPP")
        let foreign = BankConnection(iban: try #require(IBAN("GB82WEST12345698765432")), currency: .eur)
        #expect(foreign.domesticAccount == nil)
        #expect(foreign.domesticLabel == "GB82 WEST 1234 5698 7654 32")
        let data = try JSONEncoder().encode(connection)
        #expect(try JSONDecoder().decode(BankConnection.self, from: data) == connection)
    }
}

@Suite struct CustomerTests {
    let prague = PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "110 00")
    let berlin = PostalAddress(street: "Hauptstraße 5", city: "Berlin", postalCode: "10115", countryCode: "DE")
    let zurich = PostalAddress(street: "Bahnhofstrasse 1", city: "Zürich", postalCode: "8001", countryCode: "CH")
    let athens = PostalAddress(street: "Ermou 1", city: "Athens", postalCode: "10563", countryCode: "GR")

    @Test func inferredStatusesAndDefaultTreatments() {
        #expect(CustomerVATStatus.inferred(vatIdentifier: VATIdentifier("CZ45274649"), countryCode: "CZ") == .czechVATPayer)
        #expect(CustomerVATStatus.inferred(vatIdentifier: nil, countryCode: "CZ") == .czechNonPayer)
        #expect(CustomerVATStatus.inferred(vatIdentifier: VATIdentifier("DE123456789"), countryCode: "DE") == .euBusiness)
        #expect(CustomerVATStatus.inferred(vatIdentifier: nil, countryCode: "DE") == .euConsumer)
        #expect(CustomerVATStatus.inferred(vatIdentifier: nil, countryCode: "gr") == .euConsumer)
        #expect(CustomerVATStatus.inferred(vatIdentifier: VATIdentifier("GR123456789"), countryCode: "GR") == .euBusiness)
        #expect(CustomerVATStatus.inferred(vatIdentifier: VATIdentifier("EL123456789"), countryCode: "GR") == .euBusiness)
        #expect(CustomerVATStatus.inferred(vatIdentifier: VATIdentifier("CHE123456789"), countryCode: "CH") == .nonEUBusiness)
        #expect(CustomerVATStatus.inferred(vatIdentifier: nil, countryCode: "US") == .nonEUConsumer)

        #expect(CustomerVATStatus.czechVATPayer.defaultServiceTreatment == .taxable(.standard))
        #expect(CustomerVATStatus.czechNonPayer.defaultServiceTreatment == .taxable(.standard))
        #expect(CustomerVATStatus.euBusiness.defaultServiceTreatment == .reverseChargeEU)
        #expect(CustomerVATStatus.euConsumer.defaultServiceTreatment == .taxable(.standard))
        #expect(CustomerVATStatus.nonEUBusiness.defaultServiceTreatment == .outsideEU)
        #expect(CustomerVATStatus.nonEUConsumer.defaultServiceTreatment == .taxable(.standard))
        #expect(CustomerVATStatus.euBusiness.requiresVATIdentifier)
        #expect(CustomerVATStatus.czechVATPayer.requiresVATIdentifier)
        #expect(!CustomerVATStatus.euConsumer.requiresVATIdentifier)
    }

    @Test func customerDefaults() {
        let czech = Customer(id: "c1", party: Party(name: " Nováková a synové s. r. o. ", address: prague, identificationNumber: IdentificationNumber("45274649"), vatIdentifier: VATIdentifier("CZ45274649")))
        #expect(czech.party.name == "Nováková a synové s. r. o.")
        #expect(czech.vatStatus == .czechVATPayer)
        #expect(czech.currency == .czk)
        #expect(czech.paymentTermDays == 14)
        #expect(czech.language == .czech)

        let german = Customer(id: "c2", party: Party(name: "Beispiel GmbH", address: berlin, vatIdentifier: VATIdentifier("DE123456789")), currency: .eur, paymentTermDays: 30)
        #expect(german.vatStatus == .euBusiness)
        #expect(german.language == .english)
        #expect(german.vatStatus.defaultServiceTreatment == .reverseChargeEU)

        let swiss = Customer(id: "c3", party: Party(name: "Beispiel AG", address: zurich, vatIdentifier: VATIdentifier("CHE123456789")), currency: .chf)
        #expect(swiss.vatStatus == .nonEUBusiness)

        let overridden = Customer(id: "c4", party: Party(name: "Someone", address: athens), vatStatus: .euBusiness, language: .czech)
        #expect(overridden.vatStatus == .euBusiness)
        #expect(overridden.language == .czech)

        let greek = Customer(id: "c5", party: Party(name: "Example AE", address: athens, vatIdentifier: VATIdentifier("GR123456789")), currency: .eur)
        #expect(greek.vatStatus == .euBusiness)
        #expect(greek.vatStatus.defaultServiceTreatment == .reverseChargeEU)
        #expect(greek.vatStatus.requiresVATIdentifier)
        #expect(greek.party.vatIdentifier?.value == "EL123456789")
    }

    @Test func customerFromDecodedLowercaseCzechAddress() throws {
        let json = #"{"street":"Dlouhá 12","city":"Praha 1","postalCode":"11000","countryCode":"cz"}"#
        let address = try JSONDecoder().decode(PostalAddress.self, from: Data(json.utf8))
        let customer = Customer(id: "c6", party: Party(name: "Novák", address: address))
        #expect(customer.language == .czech)
        #expect(customer.vatStatus == .czechNonPayer)
    }

    @Test func codable() throws {
        let customer = Customer(id: "c2", party: Party(name: "Beispiel GmbH", address: berlin, vatIdentifier: VATIdentifier("DE123456789"), email: "x@example.com"), currency: .eur)
        let data = try JSONEncoder().encode(customer)
        let back = try JSONDecoder().decode(Customer.self, from: data)
        #expect(back == customer)
    }
}
