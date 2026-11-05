// One row of a documents table, derived from a DocumentState, plus the small formatting helpers the
// lists share (screens-flows.md §2b).

import Foundation
import InvoicingCore
import InvoicingData
import SwiftUI

struct DocumentRow: Identifiable, Hashable {
    let state: DocumentState

    var id: String { state.id }
    var summary: DocumentSummary { state.summary }
    var isDraft: Bool { summary.status == .draft }
    var number: String { summary.number ?? "" }
    var kind: DocumentKind { summary.kind }
    var typeName: String { String(localized: kind.shortTitle) }
    var customerName: String { summary.customerName }
    var issueDate: CalendarDay { summary.issueDate }
    var dueDate: CalendarDay { summary.dueDate }
    var total: Decimal { summary.totalGross?.amount ?? 0 }
    var outstanding: Decimal { state.outstanding.amount }
    var currencyCode: String { summary.currency.code }
    var variableSymbol: String { summary.variableSymbol ?? "" }
    var badgeInputs: DocumentStateInputs { DocumentStateInputs(state) }

    /// The badge detail: "+12 dní · zbývá 1 000,00 €" when overdue, the final invoice numbers for a
    /// deducted advance (design-system.md §4.3).
    func badgeDetail(locale: Locale) -> String? {
        if state.isOverdue {
            let left = MoneyText.format(state.outstanding.amount, currency: currencyCode, locale: locale)
            return String(localized: L.overdueDetail(state.daysOverdue, left))
        }
        if state.deductedInFinal, !state.deductedBy.isEmpty {
            return state.deductedBy.joined(separator: ", ")
        }
        return nil
    }

    /// Search over number, client, variable symbol and amounts, ignoring case and diacritics.
    func matches(search: String) -> Bool {
        let needle = search.folded
        guard !needle.isEmpty else { return true }
        return [number, customerName, variableSymbol, total.description, outstanding.description]
            .contains { $0.folded.contains(needle) }
    }
}

extension String {
    /// Lower-case and without diacritics, for matching what the user typed ("Novak" finds "Novák").
    var folded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

extension DocumentKind {
    /// The short type names of the lists (screens-flows.md §5): Faktura / Zálohová / DDPP / Konečná.
    var shortTitle: LocalizedStringResource {
        switch self {
        case .invoice: L.typeInvoice
        case .advanceRequest: L.typeAdvance
        case .paymentTaxDocument: L.typePaymentTaxDocument
        case .finalInvoice: L.typeFinal
        }
    }

    var symbol: String {
        switch self {
        case .invoice: Symbols.document
        case .advanceRequest: Symbols.advance
        case .paymentTaxDocument: Symbols.receipt
        case .finalInvoice: Symbols.finalInvoice
        }
    }
}

extension DocumentPaymentKind {
    var title: LocalizedStringResource {
        switch self {
        case .received: L.paymentReceived
        case .refund: L.paymentRefund
        case .creditIn: L.paymentCreditIn
        case .creditOut: L.paymentCreditOut
        }
    }
}

extension DocumentLanguage {
    /// The document language closest to the UI locale, for titles shown in the app itself.
    static func ui(_ locale: Locale) -> DocumentLanguage {
        locale.language.languageCode?.identifier == "cs" ? .czech : .english
    }
}

extension DocumentStateInputs {
    /// The badge inputs from the data layer's state, one to one (ADR 0007). The raw values of the kinds
    /// and settlements match, so an unknown value falls back to the neutral case.
    init(_ state: DocumentState) {
        self.init(
            kind: Kind(rawValue: state.summary.kind.rawValue) ?? .invoice,
            settlement: Settlement(rawValue: state.settlement.rawValue) ?? .open,
            isOverdue: state.isOverdue,
            taxDocumentRequired: state.taxDocumentRequired,
            taxDocumentIssued: state.taxDocumentIssued,
            deductedInFinal: state.deductedInFinal,
            markedForCreditNote: state.markedForCreditNote)
    }
}

/// A calendar day in the UI locale, without time-zone arithmetic (the day is local by definition).
struct DayText: View {
    let day: CalendarDay

    init(_ day: CalendarDay) {
        self.day = day
    }

    var body: some View {
        Text(day.midnight(in: .current), format: .dateTime.day().month(.defaultDigits).year())
            .textRole(.body)
    }
}

extension CalendarDay {
    /// The day formatted for the UI locale, for strings (tooltips, captions).
    func formatted(_ locale: Locale) -> String {
        midnight(in: .current).formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale))
    }
}

/// Amounts per currency, never summed across currencies (screens-flows.md §2a).
enum MoneyList {
    /// One entry per currency, sorted by currency code.
    static func sums(_ monies: [Money]) -> [Money] {
        var totals: [String: Money] = [:]
        for money in monies {
            if let existing = totals[money.currency.code] {
                totals[money.currency.code] = existing + money
            } else {
                totals[money.currency.code] = money
            }
        }
        return totals.keys.sorted().compactMap { totals[$0] }
    }

    /// "18 400,00 € + 35 000,00 Kč"; a dash when there is nothing.
    static func text(_ monies: [Money], locale: Locale) -> String {
        let sums = sums(monies)
        guard !sums.isEmpty else { return "—" }
        return sums.map { MoneyText.format($0.amount, currency: $0.currency.code, locale: locale) }.joined(separator: " + ")
    }
}
