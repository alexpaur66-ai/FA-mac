// Exchange rates (screens-flows.md §2g): the stored ČNB rates per currency and the file import.
// The app has no network access, so the rates come from the ČNB text files Saša downloads, or are
// typed on the document (decision of 5 Nov 2026).

import InvoicingCore
import InvoicingData
import SwiftUI
import UniformTypeIdentifiers

struct RateRow: Identifiable, Hashable {
    let rate: ExchangeRate

    var id: String { rate.currency.code + "|" + rate.validFor.isoString + "|" + sourceName }
    var day: CalendarDay { rate.validFor }
    var value: Decimal { rate.czkPerAmount }
    var amount: Int { rate.amount }

    var sourceName: String { RateSourceName.text(rate.source) }

    /// "1 EUR = 24,315 CZK" (screens-flows.md §2g), with the quoted amount when the ČNB quotes per 100.
    func rateText(locale: Locale) -> String {
        let rate = value.formatted(Decimal.FormatStyle.number.precision(.fractionLength(3)).locale(locale))
        return amount == 1
            ? String(localized: L.rateEquals(self.rate.currency.code, rate))
            : String(localized: L.rateEqualsAmount(amount, self.rate.currency.code, rate))
    }
}

struct RatesView: View {
    let stores: Stores
    /// Bumped after each import; the window holds it so the coverage column reloads too.
    @Binding var version: Int
    /// The file importer; File ▸ Import ČNB Rates… opens it from anywhere.
    @Binding var importing: Bool
    /// The result line of an import, shown by the window at the top of the content pane; true marks an error.
    let report: @MainActor (String, Bool) -> Void

    /// The currencies Saša invoices in (decision of 5 Nov 2026).
    static let currencies: [Currency] = [.eur, .usd]

    @State private var currencyCode = "EUR"
    @State private var rows: [RateRow] = []
    @State private var sortOrder = [KeyPathComparator(\RateRow.day, order: .reverse)]
    @Environment(\.locale) private var locale

    private struct LoadKey: Equatable {
        let currency: String
        let version: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker(selection: $currencyCode) {
                    ForEach(Self.currencies, id: \.code) { currency in
                        Text(verbatim: currency.code).tag(currency.code)
                    }
                } label: {
                    Text(L.colCurrency)
                }
                .fixedSize()
                Spacer()
            }
            .padding(Spacing.m)
            if rows.isEmpty {
                ContentUnavailableView {
                    Label { Text(L.noRates) } icon: { Image(systemName: "arrow.left.arrow.right") }
                } description: {
                    Text(L.noRatesDescription)
                } actions: {
                    Button { importing = true } label: { Text(L.importRates) }
                }
            } else {
                Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn(Text(L.colDate), value: \.day) { row in DayText(row.day) }
                        .width(min: 90, ideal: 110)
                    TableColumn(Text(L.colRate), value: \.value) { row in
                        Text(verbatim: row.rateText(locale: locale)).textRole(.amount)
                    }
                    .width(min: 150, ideal: 190)
                    .alignment(.trailing)
                    TableColumn(Text(L.colSource), value: \.sourceName) { row in
                        Text(verbatim: row.sourceName).textRole(.body)
                    }
                }
            }
        }
        .navigationTitle(Text(L.rates))
        .toolbar {
            ToolbarItem {
                Button { importing = true } label: {
                    Label { Text(L.importRates) } icon: { Image(systemName: "tray.and.arrow.down") }
                }
                .help(Text(L.importRatesHelp))
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .data], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .task(id: LoadKey(currency: currencyCode, version: version)) {
            load()
        }
    }

    private func load() {
        rows = ((try? stores.rates.rates(for: Currency.known(currencyCode))) ?? []).map { RateRow(rate: $0) }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let outcome = RateImport.perform(result, stores: stores, locale: locale) else { return }
        if let count = outcome.count {
            report(Count.ratesImported(count), false)
            version += 1
        } else {
            report(outcome.line, true)
        }
    }
}

/// The detail column of the rates section: the latest stored day per currency.
struct RatesCoverageView: View {
    let stores: Stores
    /// The window's import counter; a change reloads the latest days.
    let version: Int
    @State private var latest: [(Currency, CalendarDay?)] = []
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L.ratesCoverage).textRole(.sectionTitle)
            ForEach(latest, id: \.0.code) { currency, day in
                LabeledContent {
                    Text(verbatim: day.map { $0.formatted(locale) } ?? "—").textRole(.body)
                } label: {
                    Text(verbatim: currency.code).textRole(.body)
                }
            }
            Text(L.ratesNote).textRole(.caption)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: version) {
            latest = RatesView.currencies.map { ($0, try? stores.rates.latestDay(for: $0)) }
        }
    }
}
