// One row of a documents table, derived from a DocumentState, plus the small formatting helpers the
// lists share (screens-flows.md §2b) and the aggregation rules every list applies (§2a).

import Foundation
import InvoicingCore
import InvoicingData
import SwiftUI

struct DocumentRow: Identifiable, Hashable {
    let state: DocumentState
    /// The day the badge details count from ("due in 5 days").
    let today: CalendarDay

    init(state: DocumentState, today: CalendarDay = CalendarDay(Date(), in: .current)) {
        self.state = state
        self.today = today
    }

    var id: String { state.id }
    var summary: DocumentSummary { state.summary }
    var isDraft: Bool { summary.status == .draft }
    var isIssued: Bool { summary.status == .issued }
    var number: String { summary.number ?? "" }
    var kind: DocumentKind { summary.kind }
    var typeName: String { String(localized: kind.shortTitle) }
    var customerName: String { summary.customerName }
    var issueDate: CalendarDay { summary.issueDate }
    var dueDate: CalendarDay { summary.dueDate }
    /// The last save, for the Drafts sort.
    var updatedAt: String { summary.updatedAt }
    /// The sort key of the Total column; a draft without computable totals sorts as zero.
    var total: Decimal { summary.totalGross?.amount ?? 0 }
    /// The total to display: nil on a draft whose totals cannot be computed yet (a missing rate).
    var totalOrNil: Decimal? { summary.totalGross?.amount }
    var outstanding: Decimal { state.outstanding.amount }
    var currencyCode: String { summary.currency.code }
    var variableSymbol: String { summary.variableSymbol ?? "" }
    var badgeInputs: DocumentStateInputs { DocumentStateInputs(state) }

    /// The badge detail (design-system.md §4.3): the days late and the open balance when overdue, the due
    /// date of an open document, what is left on a partly paid one, the surplus of an overpaid one, the
    /// final invoice numbers of a deducted advance, the reason of a closing event.
    func badgeDetail(locale: Locale) -> String? {
        if let closure = state.closure {
            return closure.reason
        }
        if state.deductedInFinal, !state.deductedBy.isEmpty {
            return state.deductedBy.joined(separator: ", ")
        }
        guard isIssued, kind != .paymentTaxDocument else { return nil }
        let left = MoneyText.format(state.outstanding.amount, currency: currencyCode, locale: locale)
        switch state.settlement {
        case .open, .partlyPaid:
            if state.isOverdue {
                return state.daysOverdue == 1
                    ? String(localized: L.overdueDetailOne(left))
                    : String(localized: L.overdueDetail(state.daysOverdue, left))
            }
            if state.settlement == .partlyPaid {
                return String(localized: L.amountLeft(left))
            }
            let days = dueDate.days(since: today)
            if days == 0 { return String(localized: L.dueToday) }
            if days == 1 { return String(localized: L.dueTomorrow) }
            return days > 1 ? String(localized: L.dueInDays(days)) : nil
        case .overpaid:
            return String(localized: L.overpaidBy(MoneyText.format(-state.outstanding.amount, currency: currencyCode, locale: locale)))
        case .paid, .settledByAdvances, .draft, .closedUnpaid:
            return nil
        }
    }

    /// Search over number, client, variable symbol and amounts, ignoring case and diacritics.
    func matches(search: String) -> Bool {
        let needle = search.folded
        guard !needle.isEmpty else { return true }
        return [number, customerName, variableSymbol, totalOrNil?.description ?? "", outstanding.description]
            .contains { $0.folded.contains(needle) }
    }
}

extension DocumentState {
    /// Record Payment… applies: an issued document with an open balance that is not a payment tax document
    /// (the store refuses those) and has no closing event. Shared by the toolbar, the context menu and the
    /// menu bar.
    var acceptsPayment: Bool {
        summary.status == .issued && summary.kind != .paymentTaxDocument && closure == nil && outstanding.amount > 0
    }

    /// Record Refund… applies: an overpaid document gives the surplus back (screens-flows.md §2f).
    var acceptsRefund: Bool {
        summary.status == .issued && summary.kind != .paymentTaxDocument && closure == nil && outstanding.amount < 0
    }

    /// The Unpaid and Overdue rules of screens-flows.md §2a: an issued invoice or final invoice with an open
    /// balance and no credit note mark. Advances have their own line.
    var countsAsUnpaidInvoice: Bool {
        summary.status == .issued
            && (summary.kind == .invoice || summary.kind == .finalInvoice)
            && (settlement == .open || settlement == .partlyPaid)
            && !markedForCreditNote
    }

    /// An issued advance request that waits for its payment or its final invoice: not deducted, not closed.
    var isOpenAdvance: Bool {
        summary.status == .issued && summary.kind == .advanceRequest && !deductedInFinal && closure == nil
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

    /// The English name of the type (screens-flows.md §5), for the detail header, the Type pop-up and the
    /// Issue sheet. The printed Czech titles stay on the PDF.
    var longTitle: LocalizedStringResource {
        switch self {
        case .invoice: L.typeLongInvoice
        case .advanceRequest: L.typeLongAdvance
        case .paymentTaxDocument: L.typeLongPaymentTaxDocument
        case .finalInvoice: L.typeLongFinal
        }
    }

    /// The menu item of Document ▸ Change Type (screens-flows.md §1.4): title case, no Czech title.
    var menuTitle: LocalizedStringResource {
        switch self {
        case .invoice: L.menuKindInvoice
        case .advanceRequest: L.menuKindAdvance
        case .paymentTaxDocument: L.menuKindPaymentTaxDocument
        case .finalInvoice: L.menuKindFinal
        }
    }

    /// "Advance invoice (Zálohová faktura)": the English name with the printed Czech title (design-system.md §9).
    var pickerTitle: String {
        String(localized: L.kindWithCzechTitle(String(localized: longTitle), title(language: .czech)))
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

extension DocumentPayment {
    /// Where the payment came from (screens-flows.md §2f): a bank statement line, applied credit, or typed in.
    var sourceTitle: LocalizedStringResource {
        if isFromBankImport { return L.sourceStatement }
        if kind == .creditIn || kind == .creditOut { return L.sourceCredit }
        return L.sourceManual
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
    /// One entry per currency, EUR first (the company's invoicing currency), then the others by code.
    static func sums(_ monies: [Money]) -> [Money] {
        var totals: [String: Money] = [:]
        for money in monies {
            if let existing = totals[money.currency.code] {
                totals[money.currency.code] = existing + money
            } else {
                totals[money.currency.code] = money
            }
        }
        let codes = totals.keys.sorted { lhs, rhs in
            if lhs == "EUR" || rhs == "EUR" { return lhs == "EUR" }
            return lhs < rhs
        }
        return codes.compactMap { totals[$0] }
    }

    /// "18 400,00 € + 35 000,00 Kč"; a dash when there is nothing.
    static func text(_ monies: [Money], locale: Locale) -> String {
        let sums = sums(monies)
        guard !sums.isEmpty else { return "—" }
        return sums.map { MoneyText.format($0.amount, currency: $0.currency.code, locale: locale) }.joined(separator: " + ")
    }
}

/// Counts in English, with the singular handled in code: the app has no string catalog with plural rules.
enum Count {
    static func documents(_ count: Int) -> String {
        count == 1 ? String(localized: L.documentCountOne) : String(localized: L.documentsCount(count))
    }

    static func daysOverdue(_ days: Int) -> String {
        days == 1 ? String(localized: L.dayOverdueOne) : String(localized: L.daysOverdue(days))
    }

    static func ratesImported(_ count: Int) -> String {
        count == 1 ? String(localized: L.importedRatesOne) : String(localized: L.importedRates(count))
    }

    static func clientDocuments(_ count: Int) -> String {
        count == 1 ? String(localized: L.clientDocumentsCountOne) : String(localized: L.clientDocumentsCount(count))
    }
}
