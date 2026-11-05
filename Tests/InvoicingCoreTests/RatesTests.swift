import Foundation
import Testing
@testable import InvoicingCore

@Suite struct CNBRateFileTests {
    /// Header lines and the EUR row are as published by the ČNB for 4 Nov 2026; the other rows are
    /// sample values for the parser, not real rates.
    static let daily = """
    04.11.2026 #212
    země|měna|množství|kód|kurz
    Austrálie|dolar|1|AUD|14,123
    EMU|euro|1|EUR|24,310
    Maďarsko|forint|100|HUF|6,200
    USA|dolar|1|USD|21,000
    """

    @Test func parsesDailyFile() throws {
        let file = try CNBRateFile.parseDaily(Self.daily)
        #expect(file.day == day("2026-11-04"))
        #expect(file.order == 212)
        #expect(file.rates.count == 4)
        let eur = try #require(file.rates.first { $0.currency == .eur })
        #expect(eur.amount == 1)
        #expect(eur.czkPerAmount == d("24.31"))
        #expect(eur.validFor == day("2026-11-04"))
        #expect(eur.source == .cnb(order: 212))
        let huf = try #require(file.rates.first { $0.currency.code == "HUF" })
        #expect(huf.amount == 100)
        #expect(huf.czkPerUnit == d("0.062"))
    }

    @Test func acceptsWindowsLineEndingsAndEnglishHeader() throws {
        let text = "03.Jan.2000 #1\r\nCountry|Currency|Amount|Code|Rate\r\nEMU|euro|1|EUR|36.127\r\n"
        let file = try CNBRateFile.parseDaily(text)
        #expect(file.day == day("2000-01-03"))
        #expect(file.order == 1)
        #expect(file.rates.first?.czkPerAmount == d("36.127"))
    }

    @Test func headerWithoutOrderNumber() throws {
        let file = try CNBRateFile.parseDaily("04.11.2026\nzemě|měna|množství|kód|kurz\nEMU|euro|1|EUR|24,310\n")
        #expect(file.order == nil)
        #expect(file.rates.first?.source == .cnb(order: nil))
    }

    @Test func skipsRowsWithoutARateButRejectsBrokenRows() throws {
        let text = """
        04.11.2026 #212
        země|měna|množství|kód|kurz
        EMU|euro|1|EUR|-
        USA|dolar|1|USD|21,000
        """
        let file = try CNBRateFile.parseDaily(text)
        #expect(file.rates.map(\.currency.code) == ["USD"])
        #expect(throws: CNBRateFile.ParseError.malformedLine(lineNumber: 3, text: "EMU|euro|1|EUR")) {
            try CNBRateFile.parseDaily("04.11.2026 #212\nzemě|měna|množství|kód|kurz\nEMU|euro|1|EUR")
        }
        #expect(throws: CNBRateFile.ParseError.malformedHeader("hello")) {
            try CNBRateFile.parseDaily("hello\nzemě|měna|množství|kód|kurz\n")
        }
        #expect(throws: CNBRateFile.ParseError.empty) { try CNBRateFile.parseDaily("") }
        #expect(throws: CNBRateFile.ParseError.empty) { try CNBRateFile.parseDaily("04.11.2026 #212\n") }
    }

    @Test func parsesYearlyFile() throws {
        // Layout of the ČNB yearly file; the values are sample data.
        let text = """
        Datum|1 AUD|1 EUR|100 HUF
        02.01.2026|13,797|24,170|6,100
        05.01.2026|13,800|24,200|6,120
        """
        let rates = try CNBRateFile.parseYearly(text)
        #expect(rates.count == 6)
        let table = ExchangeRateTable(rates: rates)
        #expect(table.days(for: .eur) == [day("2026-01-02"), day("2026-01-05")])
        #expect(table.rate(for: .eur, on: day("2026-01-05"))?.czkPerAmount == d("24.2"))
        let huf = try #require(table.rate(for: Currency.known("HUF"), on: day("2026-01-02")))
        #expect(huf.amount == 100)
        #expect(huf.czkPerAmount == d("6.1"))
        #expect(huf.source == .cnb(order: nil))
    }

    @Test func yearlyFileEnglishHeaderAndErrors() throws {
        let rates = try CNBRateFile.parseYearly("Date|1 EUR\n03.Jan.2000|36.127\n")
        #expect(rates.count == 1)
        #expect(rates[0].validFor == day("2000-01-03"))
        #expect(throws: CNBRateFile.ParseError.malformedHeader("Foo|1 EUR")) {
            try CNBRateFile.parseYearly("Foo|1 EUR\n02.01.2026|24,170\n")
        }
        #expect(throws: CNBRateFile.ParseError.malformedHeader("Datum|EUR")) {
            try CNBRateFile.parseYearly("Datum|EUR\n02.01.2026|24,170\n")
        }
        #expect(throws: CNBRateFile.ParseError.unknownDate("nope")) {
            try CNBRateFile.parseYearly("Datum|1 EUR\nnope|24,170\n")
        }
        #expect(throws: CNBRateFile.ParseError.malformedLine(lineNumber: 2, text: "02.01.2026")) {
            try CNBRateFile.parseYearly("Datum|1 EUR\n02.01.2026\n")
        }
        #expect(throws: CNBRateFile.ParseError.empty) { try CNBRateFile.parseYearly("") }
    }
}

@Suite struct ExchangeRateTableTests {
    func rate(_ iso: String, _ value: String) -> ExchangeRate {
        ExchangeRate(currency: .eur, czkPerAmount: d(value), validFor: day(iso), source: .cnb(order: nil))
    }

    @Test func weekendFallsBackToLastPublishedRate() {
        let table = ExchangeRateTable(rates: [rate("2026-11-05", "24.3"), rate("2026-11-06", "24.35"), rate("2026-11-04", "24.31")])
        #expect(table.count == 3)
        #expect(table.latestDay(for: .eur) == day("2026-11-06"))
        #expect(table.rate(for: .eur, on: day("2026-11-07"))?.validFor == day("2026-11-06"))  // Saturday
        #expect(table.rate(for: .eur, on: day("2026-11-08"))?.validFor == day("2026-11-06"))  // Sunday
        #expect(table.rate(for: .eur, on: day("2026-11-05"))?.czkPerAmount == d("24.3"))
        #expect(table.rate(for: .eur, on: day("2026-11-07"), lookup: .exactDay) == nil)
        #expect(table.rate(for: .eur, on: day("2026-11-03")) == nil)   // nothing published before
        #expect(table.rate(for: .usd, on: day("2026-11-05")) == nil)
        #expect(table.latestDay(for: .usd) == nil)
    }

    @Test func mergeReplacesSameDay() {
        var table = ExchangeRateTable(rates: [rate("2026-11-05", "24.3")])
        table.merge([rate("2026-11-05", "24.4")])
        #expect(table.count == 1)
        #expect(table.rate(for: .eur, on: day("2026-11-05"))?.czkPerAmount == d("24.4"))
        #expect(!table.isEmpty)
        #expect(ExchangeRateTable().isEmpty)
    }
}

@Suite struct ExchangeRateTests {
    @Test func convertsToCZK() {
        let eur = ExchangeRate(currency: .eur, czkPerAmount: d("24.310"), validFor: day("2026-11-04"), source: .cnb(order: 212))
        #expect(eur.czkPerUnit == d("24.31"))
        #expect(eur.toCZK(Money(100, .eur)) == Money(2431, .czk))
        #expect(eur.toCZK(Money(d("1234.56"), .eur)) == Money(d("30012.15"), .czk))  // 30012.1536
        #expect(eur.toCZK(d("1234.56")) == d("30012.15"))
        #expect(eur.toCZK(d("1234.56"), scale: 3) == d("30012.154"))
        let huf = ExchangeRate(currency: Currency.known("HUF"), amount: 100, czkPerAmount: d("6.2"), validFor: day("2026-11-04"), source: .manual)
        #expect(huf.toCZK(Money(1000, Currency.known("HUF"))) == Money(62, .czk))
        #expect(huf.czkPerUnit == d("0.062"))
    }

    @Test func czechLabels() {
        let eur = ExchangeRate(currency: .eur, czkPerAmount: d("24.31"), validFor: day("2026-11-04"), source: .cnb(order: 212))
        #expect(eur.czechLabel == "24,310 CZK/EUR")
        let huf = ExchangeRate(currency: Currency.known("HUF"), amount: 100, czkPerAmount: d("6.2"), validFor: day("2026-11-04"), source: .manual)
        #expect(huf.czechLabel == "6,200 CZK/100 HUF")
    }

    @Test func codable() throws {
        let eur = ExchangeRate(currency: .eur, czkPerAmount: d("24.31"), validFor: day("2026-11-04"), source: .cnb(order: 212))
        let data = try JSONEncoder().encode(eur)
        let back = try JSONDecoder().decode(ExchangeRate.self, from: data)
        #expect(back == eur)
    }
}
