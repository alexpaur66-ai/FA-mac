import Foundation
import Testing
@testable import InvoicingCore

@Suite struct CompanyProfileTests {
    static func account(_ iban: String, currency: Currency?) throws -> BankConnection {
        BankConnection(iban: try #require(IBAN(iban)), currency: currency)
    }

    @Test func picksTheAccountKeptInTheDocumentCurrency() throws {
        let czk = try Self.account("CZ6508000000192000145399", currency: .czk)
        let eur = try Self.account("DE89370400440532013000", currency: .eur)
        let profile = CompanyProfile(supplier: DocumentFixtures.supplier, bankConnections: [czk, eur])
        #expect(profile.bankConnection(for: .eur) == eur)
        #expect(profile.bankConnection(for: .czk) == czk)
        // No account in USD and no multi-currency account: the first account is printed.
        #expect(profile.bankConnection(for: .usd) == czk)
    }

    @Test func prefersAMultiCurrencyAccountOverTheFirstOne() throws {
        let czk = try Self.account("CZ6508000000192000145399", currency: .czk)
        let any = try Self.account("DE89370400440532013000", currency: nil)
        let profile = CompanyProfile(supplier: DocumentFixtures.supplier, bankConnections: [czk, any])
        #expect(profile.bankConnection(for: .eur) == any)
        #expect(profile.bankConnection(for: .czk) == czk)
        #expect(CompanyProfile(supplier: DocumentFixtures.supplier).bankConnection(for: .czk) == nil)
    }

    @Test func defaultsAndCodable() throws {
        let profile = CompanyProfile(supplier: DocumentFixtures.supplier, bankConnections: [DocumentFixtures.bank],
                                     defaultCurrency: .eur, defaultPaymentTermDays: -3, footer: "Děkujeme.")
        #expect(profile.isVATPayer)
        #expect(profile.defaultPaymentTermDays == 0)
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(CompanyProfile.self, from: data) == profile)
    }
}
