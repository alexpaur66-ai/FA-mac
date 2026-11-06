// The ČNB file import shared by File ▸ Import ČNB Rates…, the Exchange Rates sheet and the editor's rate
// form (screens-flows.md §2c, §2g), and the one place that names a rate's source.

import Foundation
import InvoicingCore

enum RateSourceName {
    /// "Typed" or "ČNB file" (screens-flows.md §5), for the rate line and the rates table.
    static func text(_ source: ExchangeRateSource) -> String {
        switch source {
        case .cnb: String(localized: L.sourceCNB)
        case .ecb: String(localized: L.sourceECB)
        case .manual: String(localized: L.sourceManual)
        case .fixedAccounting: String(localized: L.sourceFixed)
        }
    }
}

@MainActor enum RateImport {
    /// Reads the chosen file as UTF-8 or Windows-1250 text and imports it with the parser its first line
    /// names, so a parse error reports the line of the format the file really has. Returns the result
    /// line for the user and the number of rates imported (nil when nothing was).
    static func perform(_ result: Result<[URL], Error>, stores: Stores, locale: Locale) -> (line: String, count: Int?)? {
        do {
            guard let url = try result.get().first else { return nil }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1250) else {
                return (String(localized: L.rateImportFailed), nil)
            }
            let count = try isYearlyFile(text) ? stores.rates.importYearly(text) : stores.rates.importDaily(text)
            return (Count.ratesImported(count), count)
        } catch {
            return (ErrorText.message(error, locale: locale), nil)
        }
    }

    /// A yearly file ("rok.txt") starts with a "Datum|1 AUD|…" header; a daily file with "04.11.2026 #212".
    nonisolated static func isYearlyFile(_ text: String) -> Bool {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard var firstLine else { return false }
        if firstLine.unicodeScalars.first == "\u{FEFF}" { firstLine.unicodeScalars.removeFirst() }
        let firstCell = firstLine.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return firstCell == "Datum" || firstCell == "Date"
    }
}
