// Exchange rates (screens-flows.md §2g): the stored ČNB rates per currency and the file import.
// The app has no network access, so the rates come from the ČNB text files Saša downloads.

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

    var sourceName: String {
        switch rate.source {
        case .cnb: String(localized: L.sourceCNB)
        case .ecb: String(localized: L.sourceECB)
        case .manual: String(localized: L.sourceManual)
        case .fixedAccounting: String(localized: L.sourceFixed)
        }
    }
}

struct RatesView: View {
    let stores: Stores

    static let currencies: [Currency] = [.eur, .usd, .gbp, .chf, .pln]

    @State private var currencyCode = "EUR"
    @State private var rows: [RateRow] = []
    @State private var importing = false
    @State private var resultLine: String?
    @State private var version = 0
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
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer()
            }
            .padding(Spacing.m)
            if rows.isEmpty {
                ContentUnavailableView {
                    Label { Text(L.noRates) } icon: { Image(systemName: "arrow.left.arrow.right") }
                } description: {
                    Text(L.ratesNote)
                } actions: {
                    Button { importing = true } label: { Text(L.importRates) }
                }
            } else {
                Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn(Text(L.colDate), value: \.day) { row in DayText(row.day) }
                        .width(min: 90, ideal: 110)
                    TableColumn(Text(L.colRate), value: \.value) { row in
                        Text(verbatim: row.value.formatted(Decimal.FormatStyle.number.precision(.fractionLength(3)).locale(locale))
                             + (row.amount == 1 ? "" : " / " + String(row.amount)))
                            .textRole(.amount)
                    }
                    .width(min: 90, ideal: 120)
                    .alignment(.trailing)
                    TableColumn(Text(L.colSource), value: \.sourceName)
                }
            }
            if let resultLine {
                Divider()
                Text(verbatim: resultLine)
                    .textRole(.caption)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(Text(L.rates))
        .toolbar {
            ToolbarItem {
                Button { importing = true } label: {
                    Label { Text(L.importRates) } icon: { Image(systemName: "tray.and.arrow.down") }
                }
                .help(Text(L.importRates))
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

    /// Reads the chosen file as UTF-8 or Windows-1250 text and tries the daily format, then the yearly one.
    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1250) else {
                resultLine = String(localized: L.rateImportFailed)
                return
            }
            let count: Int
            if let daily = try? stores.rates.importDaily(text) {
                count = daily
            } else {
                count = try stores.rates.importYearly(text)
            }
            resultLine = String(localized: L.importedRates(count))
            version += 1
        } catch {
            resultLine = String(localized: L.rateImportFailed) + " (" + String(describing: error) + ")"
        }
    }
}

/// The detail column of the rates section: the latest stored day per currency.
struct RatesCoverageView: View {
    let stores: Stores
    @State private var latest: [(Currency, CalendarDay?)] = []
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L.ratesCoverage).textRole(.sectionTitle)
            ForEach(latest, id: \.0.code) { currency, day in
                LabeledContent {
                    Text(verbatim: day.map { $0.formatted(locale) } ?? "—").textRole(.body)
                } label: {
                    Text(verbatim: currency.code)
                }
            }
            Text(L.ratesNote).textRole(.caption)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            latest = RatesView.currencies.map { ($0, try? stores.rates.latestDay(for: $0)) }
        }
    }
}
