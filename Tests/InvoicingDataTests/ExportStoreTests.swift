import Foundation
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct ExportStoreTests {
    private let november = Fixtures.day("2026-11-01")
    private let today = Fixtures.day("2026-11-15")

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fa-mac-export-\(UUID().uuidString)", isDirectory: true)
    }

    /// November 2026: a CZK invoice, an EUR reverse-charge invoice, an advance with its payment and the
    /// payment tax document for it.
    private func issueNovember(_ database: AppDatabase) throws {
        try Fixtures.addAdvanceSeries(database)
        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        _ = try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        try documents.saveDraft(Fixtures.eurDraft(), now: Fixtures.now)
        _ = try documents.issue(id: "doc-eu", seriesID: "fv", now: Fixtures.now)
        let advance = try Fixtures.issuedAdvance(database)
        _ = try Fixtures.issuedReceipt(database, advance: advance)
    }

    /// The CSV as rows of fields, the header first (the fixtures put no delimiter inside a field).
    private func rows(_ csv: String) -> [[String]] {
        csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.map { $0.components(separatedBy: ";") }
    }

    private func value(_ row: [String], _ column: String) -> String? {
        guard let index = AccountantCSV.documentColumns.firstIndex(of: column), index < row.count else { return nil }
        return row[index]
    }

    @Test func theMonthHoldsItsDocumentsAndPayments() throws {
        let database = try Fixtures.prepared()
        try issueNovember(database)
        let store = ExportStore(database)
        let data = try store.data(month: november, today: today)
        #expect(data.documents.count == 4)
        #expect(data.advanceCount == 1)
        #expect(data.payments.count == 1)
        // VAT of the tax documents only: 2 100 on the invoice and 2 100 on the payment tax document; the
        // reverse charge carries none and the advance is not a tax document.
        #expect(data.vatCZK == Fixtures.d("4200"))
        let october = try store.data(month: Fixtures.day("2026-10-01"), today: today)
        #expect(october.documents.isEmpty && october.payments.isEmpty)
    }

    @Test func theDocumentsCSVHasFixedColumns() throws {
        let database = try Fixtures.prepared()
        try issueNovember(database)
        let data = try ExportStore(database).data(month: november, today: today)
        let table = rows(AccountantCSV.documents(data))
        #expect(table.first == AccountantCSV.documentColumns)
        #expect(table.count == 5)
        #expect(table.allSatisfy { $0.count == AccountantCSV.documentColumns.count })

        let invoice = try #require(table.first { $0.first == "FV-2026-001" })
        #expect(value(invoice, "Type") == "Faktura – daňový doklad")
        #expect(value(invoice, "Daňový doklad") == "ano")
        #expect(value(invoice, "DUZP") == "04.11.2026")
        #expect(value(invoice, "IČO") == "25596641")
        #expect(value(invoice, "VAT treatment") == "DPH 21 %")
        #expect(value(invoice, "Total") == "12100,00")
        #expect(value(invoice, "Base21") == "10000,00")
        #expect(value(invoice, "VAT21") == "2100,00")
        #expect(value(invoice, "VAT21_CZK") == "2100,00")
        #expect(value(invoice, "BaseRC") == "")
        #expect(value(invoice, "Rate") == "")
        #expect(value(invoice, "Status") == "Awaiting payment")

        let euro = try #require(table.first { $0.first == "FV-2026-002" })
        #expect(value(euro, "Currency") == "EUR")
        #expect(value(euro, "BaseRC") == "1000,00")
        #expect(value(euro, "BaseRC_CZK") == "24310,00")
        #expect(value(euro, "VAT21") == "")
        #expect(value(euro, "Rate") == "24,310")
        #expect(value(euro, "RateDate") == "04.11.2026")
        #expect(value(euro, "RateSource") == "ČNB")
        #expect(value(euro, "RateIsFallback") == "ne")
        #expect(value(euro, "Country") == "DE")

        let advance = try #require(table.first { $0.first == "ZF-2026-001" })
        #expect(value(advance, "Daňový doklad") == "ne")
        #expect(value(advance, "DUZP") == "")
        #expect(value(advance, "Base21") == "")
        #expect(value(advance, "VAT21_CZK") == "")
        #expect(value(advance, "Paid amount") == "12100,00")
        #expect(value(advance, "Paid date") == "10.11.2026")

        let receipt = try #require(table.first { $0.first == "DD-2026-001" })
        #expect(value(receipt, "Daňový doklad") == "ano")
        #expect(value(receipt, "RelatedDocs") == "ZF-2026-001")
        #expect(value(receipt, "VAT21") == "2100,00")
        #expect(value(receipt, "Paid amount") == "")
    }

    @Test func thePaymentsCSVListsThePaymentsOfTheMonth() throws {
        let database = try Fixtures.prepared()
        try issueNovember(database)
        let data = try ExportStore(database).data(month: november, today: today)
        let table = rows(AccountantCSV.payments(data))
        #expect(table.first == AccountantCSV.paymentColumns)
        #expect(table.dropFirst().map { $0 } == [[
            "10.11.2026", "ZF-2026-001", "Zálohová faktura", "Odběratel s. r. o.", "Received", "12100,00", "CZK", "DD-2026-001", "Typed", "",
        ]])
    }

    @Test func aFinalInvoiceNamesWhatItDeducts() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let advance = try Fixtures.issuedAdvance(database)
        let receipt = try Fixtures.issuedReceipt(database, advance: advance, amount: Fixtures.d("6050"))
        let documents = DocumentStore(database)
        var final = try Fixtures.finalInvoiceDraft(deducting: receipt)
        final.taxPointDate = Fixtures.day("2026-11-12")
        final.issueDate = Fixtures.day("2026-11-12")
        try documents.saveDraft(final, now: Fixtures.now)
        _ = try documents.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        let data = try ExportStore(database).data(month: november, today: today)
        let row = try #require(rows(AccountantCSV.documents(data)).first { $0.first == "FV-2026-001" })
        #expect(value(row, "RelatedDocs") == "ZF-2026-001, DD-2026-001")
        #expect(value(row, "Total") == "12100,00")
        #expect(value(row, "DeductedAdvance") == "6050,00")
        #expect(value(row, "DeductedVAT_CZK") == "1050,00")
        // The final invoice taxes the difference (§ 37a ZDPH): 10 000 − 5 000 base, 2 100 − 1 050 VAT.
        #expect(value(row, "Base21") == "5000,00")
        #expect(value(row, "VAT21") == "1050,00")
    }

    @Test func goodsCountInTheMonthOfTheirSection22Day() throws {
        let database = try Fixtures.prepared()
        let documents = DocumentStore(database)
        // Supplied on 20 October, invoiced on 5 November before the 15th: the issue date, so November.
        var goods = Fixtures.eurDraft(id: "goods")
        goods.lines[0].treatment = .intraCommunityGoods
        goods.taxPointDate = Fixtures.day("2026-10-20")
        goods.exchangeRate = ExchangeRate(currency: .eur, czkPerAmount: Fixtures.d("24.300"), validFor: Fixtures.day("2026-11-04"),
                                          source: .cnb(order: 212))
        try documents.saveDraft(goods, now: Fixtures.now)
        _ = try documents.issue(id: "goods", seriesID: "fv", now: Fixtures.now)
        let store = ExportStore(database)
        let inNovember = try store.data(month: november, today: today)
        #expect(inNovember.documents.map(\.document.id) == ["goods"])
        let row = try #require(rows(AccountantCSV.documents(inNovember)).dropFirst().first)
        #expect(value(row, "BaseExempt") == "1000,00")
        #expect(value(row, "VAT treatment") == "dodání zboží do jiného členského státu")
        // The rate of 4 November for the § 22 day of 5 November: the last one published.
        #expect(value(row, "RateIsFallback") == "ano")
        #expect(try store.data(month: Fixtures.day("2026-10-01"), today: today).documents.isEmpty)
    }

    @Test func anExportWritesTwoFilesAndRemembersTheMonth() throws {
        let database = try Fixtures.prepared()
        try issueNovember(database)
        let store = ExportStore(database)
        let folder = temporaryFolder().appendingPathComponent(AccountantCSV.folderName(november), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let files = try store.write(try store.data(month: november, today: today), to: folder, now: Fixtures.now)
        #expect(files.map(\.lastPathComponent) == ["Documents 2026-11.csv", "Payments 2026-11.csv"])
        let bytes = try Data(contentsOf: files[0])
        #expect(Array(bytes.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let record = try #require(try store.record(month: november))
        #expect(record.folder == folder.path)
        #expect(record.documents.count == 4)
        let last = try store.lastFolder()
        #expect(last == folder.path)
        let changes = try store.changedAfterExport()
        #expect(changes.isEmpty)
        let audit = try AuditLog(database).events(entity: "monthExport", id: "2026-11")
        #expect(audit.map(\.action) == ["exported"])
    }

    @Test func aDocumentIssuedIntoAnExportedMonthShowsUntilTheMonthIsExportedAgain() throws {
        let database = try Fixtures.prepared()
        try issueNovember(database)
        let store = ExportStore(database)
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try store.write(try store.data(month: november, today: today), to: folder, now: Fixtures.now)

        let documents = DocumentStore(database)
        let later = Fixtures.now.addingTimeInterval(3600)
        try documents.saveDraft(Fixtures.czkDraft(id: "late"), now: later)
        _ = try documents.issue(id: "late", seriesID: "fv", now: later)
        // A document of a month never exported (DUZP in October) is no export's concern.
        var october = Fixtures.czkDraft(id: "october")
        october.taxPointDate = Fixtures.day("2026-10-30")
        try documents.saveDraft(october, now: later)
        _ = try documents.issue(id: "october", seriesID: "fv", now: later)

        let changes = try store.changedAfterExport()
        #expect(changes.map(\.changedCount) == [1])
        #expect(changes.first?.export.month == november)

        try store.write(try store.data(month: november, today: today), to: folder, now: later.addingTimeInterval(60))
        let afterAgain = try store.changedAfterExport()
        #expect(afterAgain.isEmpty)
        let record = try store.record(month: november)
        #expect(record?.documents.count == 5)
    }

    @Test func fieldsAreQuotedAndFormulasDefused() {
        #expect(AccountantCSV.quoted("Acme; s.r.o.") == "\"Acme; s.r.o.\"")
        #expect(AccountantCSV.quoted("Say \"hi\"") == "\"Say \"\"hi\"\"\"")
        #expect(AccountantCSV.quoted("a\r\nb") == "\"a\r\nb\"")
        #expect(AccountantCSV.quoted("a\nb") == "\"a\nb\"")
        #expect(AccountantCSV.text("\r\nx") == "'\r\nx")
        #expect(AccountantCSV.text("=SUM(A1)") == "'=SUM(A1)")
        #expect(AccountantCSV.text("Acme") == "Acme")
        #expect(AccountantCSV.amount(Fixtures.d("-12.5"), scale: 2) == "-12,50")
        #expect(AccountantCSV.date(Fixtures.day("2026-01-05")) == "05.01.2026")
    }
}
