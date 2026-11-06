// File ▸ Exchange Rates (screens-flows.md §2g): a read-only sheet with the stored rates of the v0.1
// currencies. Typing the rate on each document is the primary path; the ČNB file import is secondary.
// The app has no network access, so rates come from the ČNB text files Saša downloads, or are typed on the
// document (decision of 5 Nov 2026). A stored rate is corrected where it is used (the draft's Change…).

import InvoicingCore
import InvoicingData
import SwiftUI
import UniformTypeIdentifiers

struct RateRow: Identifiable, Hashable {
    let rate: ExchangeRate

    var id: String { rate.currency.code + "|" + rate.validFor.isoString + "|" + sourceName }
    var day: CalendarDay { rate.validFor }
    var currencyCode: String { rate.currency.code }
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

/// The file types the ČNB import accepts: the daily and yearly files are plain text.
enum RateFileTypes {
    static let allowed: [UTType] = [.plainText, .text, .data]
}

struct ExchangeRatesSheet: View {
    let stores: Stores

    /// The currencies Saša invoices in (decision of 5 Nov 2026); other currencies of an imported file are
    /// stored for later.
    static let currencies: [Currency] = [.eur, .usd]

    @State private var rows: [RateRow] = []
    @State private var latest: [(Currency, CalendarDay?)] = []
    @State private var sortOrder = [KeyPathComparator(\RateRow.day, order: .reverse)]
    @State private var importing = false
    /// The last import's line: the count, or why the file was not read.
    @State private var importLine: (text: String, isError: Bool)?
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L.menuRates).textRole(.screenTitle)
            Text(latestLine).textRole(.body)
            if rows.isEmpty {
                ContentUnavailableView {
                    Label { Text(L.noRates) } icon: { Image(systemName: "arrow.left.arrow.right") }
                } description: {
                    Text(L.noRatesDescription)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
            if let loadError {
                InlineMessage(loadError)
            }
            if let importLine {
                if importLine.isError {
                    InlineMessage(importLine.text)
                } else {
                    Text(verbatim: importLine.text).textRole(.caption)
                }
            }
            HStack {
                Button { importing = true } label: { Text(L.importRates) }
                    .buttonStyle(.bordered)
                Spacer()
                Button { dismiss() } label: { Text(L.close) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .exchangeRatesSheetSized()
        .onExitCommand { dismiss() }
        .fileImporter(isPresented: $importing, allowedContentTypes: RateFileTypes.allowed, allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .task { load() }
    }

    private var table: some View {
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn(Text(L.colDate), value: \.day) { row in DayText(row.day) }
                .width(min: 90, ideal: 110)
            TableColumn(Text(L.colCurrency), value: \.currencyCode) { row in
                Text(verbatim: row.currencyCode).textRole(.body)
            }
            .width(min: 60, ideal: 70)
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

    /// "Latest: EUR 30. 10. 2026 · USD —".
    private var latestLine: LocalizedStringResource {
        func text(_ currency: Currency) -> String {
            latest.first { $0.0 == currency }?.1.map { $0.formatted(locale) } ?? "—"
        }
        return L.ratesLatest(text(.eur), text(.usd))
    }

    private func load() {
        do {
            rows = try Self.currencies.flatMap { try stores.rates.rates(for: $0) }.map { RateRow(rate: $0) }
            latest = try Self.currencies.map { ($0, try stores.rates.latestDay(for: $0)) }
            loadError = nil
        } catch {
            loadError = ErrorText.message(error, locale: locale)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let outcome = RateImport.perform(result, stores: stores, locale: locale) else { return }
        if let count = outcome.count {
            importLine = (Count.ratesImported(count), false)
            load()
        } else {
            importLine = (outcome.line, true)
        }
    }
}

private extension View {
    /// Resizable, as design-system.md §5.3 sizes it: fitted to the content on macOS 15, the frame alone on 14.
    @ViewBuilder func exchangeRatesSheetSized() -> some View {
        let framed = frame(
            minWidth: LayoutMetrics.importReviewMinSize.width, idealWidth: LayoutMetrics.importReviewIdealSize.width,
            minHeight: LayoutMetrics.importReviewMinSize.height, idealHeight: LayoutMetrics.importReviewIdealSize.height)
        if #available(macOS 15, *) {
            framed.presentationSizing(.fitted)
        } else {
            framed
        }
    }
}
