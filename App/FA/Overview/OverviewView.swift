// Overview (screens-flows.md §2a): the month bar, four tiles, the attention queue, and the
// Getting started card on a fresh database (§2j). Everything is computed from the live document states.

import InvoicingCore
import InvoicingData
import SwiftUI

struct OverviewView: View {
    let stores: Stores
    let documents: DocumentListModel
    @Binding var selection: String?
    let show: @MainActor (SidebarItem) -> Void
    let newDocument: @MainActor (DocumentKind) -> Void

    @State private var month: CalendarDay
    @State private var setup = SetupStatus()
    @Environment(\.locale) private var locale

    init(stores: Stores, documents: DocumentListModel, selection: Binding<String?>,
         show: @escaping @MainActor (SidebarItem) -> Void, newDocument: @escaping @MainActor (DocumentKind) -> Void) {
        self.stores = stores
        self.documents = documents
        self._selection = selection
        self.show = show
        self.newDocument = newDocument
        _month = State(initialValue: CalendarDay(Date(), in: .current).startOfMonth)
    }

    var body: some View {
        let figures = OverviewFigures(states: documents.states, month: month, today: documents.today)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                if !setup.isComplete {
                    gettingStarted
                }
                monthBar
                tiles(figures)
                queue(figures)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(L.overview))
        .task(id: documents.states) {
            setup = SetupStatus.load(stores)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button { newDocument(.invoice) } label: {
                        Label { Text(L.newInvoice) } icon: { Image(systemName: DocumentKind.invoice.symbol) }
                    }
                    Button { newDocument(.advanceRequest) } label: {
                        Label { Text(L.newAdvance) } icon: { Image(systemName: DocumentKind.advanceRequest.symbol) }
                    }
                } label: {
                    Label { Text(L.new) } icon: { Image(systemName: "plus") }
                } primaryAction: {
                    newDocument(.invoice)
                }
                .help(Text(L.newInvoice))
            }
        }
    }

    // MARK: Getting started

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L.gettingStarted).textRole(.sectionTitle)
            Text(L.setupIntro).textRole(.body)
            step(done: setup.hasProfile, title: L.stepCompany) {
                SettingsLink { Text(L.openSettings) }
            }
            step(done: setup.hasBankAccount, title: L.stepBank) {
                SettingsLink { Text(L.openSettings) }
            }
            step(done: setup.hasSeries, title: L.stepSeries) {
                SettingsLink { Text(L.openSettings) }
            }
            step(done: setup.hasRates, title: L.stepRates) {
                Button { show(.section(.rates)) } label: { Text(L.rates) }
            }
        }
        .padding(Spacing.l)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.l))
    }

    private func step<Action: View>(done: Bool, title: LocalizedStringResource, @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            Text(title).textRole(.body)
            Spacer()
            if !done {
                action()
            }
        }
    }

    // MARK: Month and tiles

    private var monthBar: some View {
        HStack(spacing: Spacing.m) {
            Button { month = month.adding(months: -1).startOfMonth } label: { Image(systemName: "chevron.left") }
                .help(Text(L.previousMonth))
            Text(verbatim: monthName(month)).textRole(.screenTitle).frame(minWidth: 160)
            Button { month = month.adding(months: 1).startOfMonth } label: { Image(systemName: "chevron.right") }
                .help(Text(L.nextMonth))
        }
    }

    private func monthName(_ day: CalendarDay) -> String {
        day.midnight(in: .current).formatted(Date.FormatStyle(locale: locale).month(.wide).year())
    }

    private func tiles(_ figures: OverviewFigures) -> some View {
        let name = monthName(month)
        // The This month filter is the month of today; for another month the tile has no list to open.
        let isCurrentMonth = month.year == documents.today.year && month.month == documents.today.month
        var issuedAction: (@MainActor () -> Void)?
        if isCurrentMonth { issuedAction = { show(.filter(.thisMonth)) } }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Spacing.l, alignment: .top)],
                         alignment: .leading, spacing: Spacing.l) {
            Tile(symbol: "clock", title: L.tileUnpaid,
                 value: MoneyList.text(figures.unpaid, locale: locale),
                 lines: [
                    String(localized: L.documentsCount(figures.unpaidCount)),
                    String(localized: L.unpaidAdvances) + ": " + String(figures.unpaidAdvancesCount) + " · " + MoneyList.text(figures.unpaidAdvances, locale: locale),
                 ]) {
                show(.filter(.unpaid))
            }
            Tile(symbol: "exclamationmark.circle", title: L.tileOverdue,
                 value: MoneyList.text(figures.overdue, locale: locale),
                 lines: [
                    String(localized: L.documentsCount(figures.overdueCount))
                        + (figures.oldestOverdueDays > 0 ? " · " + String(localized: L.oldestOverdue(figures.oldestOverdueDays)) : ""),
                    String(localized: L.overdueAdvances) + ": " + String(figures.overdueAdvancesCount),
                 ]) {
                show(.filter(.overdue))
            }
            Tile(symbol: Symbols.document, title: L.tileIssued(name),
                 value: figures.issuedCountsText,
                 lines: [String(localized: L.revenueTaxDocuments) + ": " + MoneyList.text(figures.revenue, locale: locale)],
                 action: issuedAction)
            // By tax point, not by issue date, so no document filter matches it; the tile opens nothing.
            Tile(symbol: "percent", title: L.tileVAT(name),
                 value: MoneyText.format(figures.vatCZK, currency: "CZK", locale: locale),
                 lines: [String(localized: L.vatTileNote)],
                 action: nil)
        }
    }

    // MARK: Queue

    private func queue(_ figures: OverviewFigures) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.needsAttention).textRole(.sectionTitle)
            if figures.queue.isEmpty {
                Label { Text(L.allCaughtUp) } icon: { Image(systemName: "checkmark.circle") }
                    .textRole(.body)
            }
            ForEach(figures.queue) { item in
                Button { selection = item.state.id } label: {
                    QueueRow(item: item, selected: selection == item.state.id)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One number tile: symbol, label, value and up to two secondary lines. Clicking opens the matching filter;
/// a tile without an action is not a button.
private struct Tile: View {
    let symbol: String
    let title: LocalizedStringResource
    let value: String
    let lines: [String]
    let action: (@MainActor () -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .textRole(.label)
            Text(verbatim: value).textRole(.total)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).textRole(.rowSecondary)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.l))
        .contentShape(RoundedRectangle(cornerRadius: Radius.l))
    }
}

private struct QueueRow: View {
    let item: OverviewFigures.QueueItem
    let selected: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        let summary = item.state.summary
        HStack(spacing: Spacing.m) {
            Image(systemName: item.symbol)
                .foregroundStyle(item.kind == .overdue ? Color.red : Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: [summary.number ?? String(localized: L.draftTitle), summary.customerName]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .textRole(.body)
                Text(item.detail).textRole(.rowSecondary)
            }
            Spacer()
            if let amount = item.amount {
                MoneyText(amount: amount.amount, currency: amount.currency.code, locale: locale)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(selected ? AnyShapeStyle(SelectionShapeStyle()) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: Radius.m))
        .contentShape(RoundedRectangle(cornerRadius: Radius.m))
    }
}

/// The figures of the Overview, computed from the states by the aggregation rules of screens-flows.md §2a.
struct OverviewFigures {
    struct QueueItem: Identifiable, Hashable {
        enum Kind: Hashable {
            case overdue, taxDocumentMissing, oldDraft
        }

        let kind: Kind
        let state: DocumentState

        var id: String { state.id + "/" + String(describing: kind) }

        /// The amount the row shows: the open balance, or a draft's total (a draft has nothing outstanding).
        /// Nil for a draft whose totals cannot be computed yet.
        var amount: Money? {
            kind == .oldDraft ? state.summary.totalGross : state.outstanding
        }

        var symbol: String {
            switch kind {
            case .overdue: "exclamationmark.circle.fill"
            case .taxDocumentMissing: "checkmark.circle.trianglebadge.exclamationmark"
            case .oldDraft: "pencil.circle"
            }
        }

        var detail: LocalizedStringResource {
            switch kind {
            case .overdue: L.daysOverdue(state.daysOverdue)
            case .taxDocumentMissing: L.queueTaxDocumentMissing
            case .oldDraft: L.queueOldDraft
            }
        }
    }

    let unpaid: [Money]
    let unpaidCount: Int
    let unpaidAdvances: [Money]
    let unpaidAdvancesCount: Int
    let overdue: [Money]
    let overdueCount: Int
    let oldestOverdueDays: Int
    let overdueAdvancesCount: Int
    let issuedCounts: [DocumentKind: Int]
    let revenue: [Money]
    /// VAT in CZK of the tax documents whose tax point falls in the month (rule marked ACCT in the spec).
    let vatCZK: Decimal
    let queue: [QueueItem]

    init(states: [DocumentState], month: CalendarDay, today: CalendarDay) {
        var unpaid: [Money] = [], unpaidAdvances: [Money] = [], overdue: [Money] = [], revenue: [Money] = []
        var unpaidCount = 0, unpaidAdvancesCount = 0, overdueCount = 0, oldest = 0, overdueAdvancesCount = 0
        var issuedCounts: [DocumentKind: Int] = [:]
        var vat = Decimal(0)
        var overdueItems: [QueueItem] = [], taxItems: [QueueItem] = [], draftItems: [QueueItem] = []

        for state in states {
            let summary = state.summary
            let isInvoice = summary.kind == .invoice || summary.kind == .finalInvoice
            let open = state.settlement == .open || state.settlement == .partlyPaid
            if summary.status == .issued {
                if isInvoice && open && !state.markedForCreditNote {
                    unpaid.append(state.outstanding)
                    unpaidCount += 1
                    if state.isOverdue {
                        overdue.append(state.outstanding)
                        overdueCount += 1
                        oldest = max(oldest, state.daysOverdue)
                    }
                }
                if summary.kind == .advanceRequest && open && !state.deductedInFinal && state.closure == nil {
                    unpaidAdvances.append(state.outstanding)
                    unpaidAdvancesCount += 1
                    if state.isOverdue { overdueAdvancesCount += 1 }
                }
                if summary.issueDate.year == month.year && summary.issueDate.month == month.month {
                    issuedCounts[summary.kind, default: 0] += 1
                    if let total = Self.revenueAmount(summary) {
                        revenue.append(total)
                    }
                }
                let taxPoint = summary.taxPointDate ?? summary.issueDate
                if summary.kind.isTaxDocument, taxPoint.year == month.year, taxPoint.month == month.month,
                   let vatCZK = summary.taxableVATCZK {
                    vat += vatCZK.amount
                }
                if Self.queuesAsOverdue(state) {
                    overdueItems.append(QueueItem(kind: .overdue, state: state))
                }
                if summary.kind == .advanceRequest && state.taxDocumentRequired && !state.taxDocumentIssued
                    && (state.settlement == .partlyPaid || state.settlement == .paid || state.settlement == .overpaid) {
                    taxItems.append(QueueItem(kind: .taxDocumentMissing, state: state))
                }
            } else if summary.issueDate.adding(days: 7) < today {
                draftItems.append(QueueItem(kind: .oldDraft, state: state))
            }
        }

        self.unpaid = MoneyList.sums(unpaid)
        self.unpaidCount = unpaidCount
        self.unpaidAdvances = MoneyList.sums(unpaidAdvances)
        self.unpaidAdvancesCount = unpaidAdvancesCount
        self.overdue = MoneyList.sums(overdue)
        self.overdueCount = overdueCount
        self.oldestOverdueDays = oldest
        self.overdueAdvancesCount = overdueAdvancesCount
        self.issuedCounts = issuedCounts
        self.revenue = MoneyList.sums(revenue)
        self.vatCZK = vat
        self.queue = overdueItems.sorted { $0.state.daysOverdue > $1.state.daysOverdue }
            + taxItems.sorted { $0.state.summary.issueDate < $1.state.summary.issueDate }
            + draftItems.sorted { $0.state.summary.issueDate < $1.state.summary.issueDate }
    }

    /// What an issued document adds to the month's revenue: tax documents only, and a final invoice net of
    /// the advances it deducts (their payment tax documents count already), so the advance money is never
    /// counted twice (§2a). `amountDue` is the supply's gross minus the deducted advances.
    static func revenueAmount(_ summary: DocumentSummary) -> Money? {
        guard summary.kind.isTaxDocument else { return nil }
        return summary.kind == .finalInvoice ? summary.amountDue : summary.totalGross
    }

    /// The overdue group of the queue: every overdue document except an advance an issued final invoice
    /// already deducted (§2a never counts it as overdue).
    static func queuesAsOverdue(_ state: DocumentState) -> Bool {
        state.isOverdue && !(state.summary.kind == .advanceRequest && state.deductedInFinal)
    }

    /// "Faktura 6 · Zálohová 2 · DDPP 1", or "0".
    var issuedCountsText: String {
        let parts = DocumentKind.allCases.compactMap { kind -> String? in
            guard let count = issuedCounts[kind], count > 0 else { return nil }
            return String(localized: kind.shortTitle) + " " + String(count)
        }
        return parts.isEmpty ? "0" : parts.joined(separator: " · ")
    }
}

/// The four required setup steps (screens-flows.md §2j).
struct SetupStatus: Equatable {
    var hasProfile = false
    var hasBankAccount = false
    var hasSeries = false
    var hasRates = false

    var isComplete: Bool { hasProfile && hasBankAccount && hasSeries && hasRates }

    static func load(_ stores: Stores) -> SetupStatus {
        var status = SetupStatus()
        if let profile = try? stores.profile.load() {
            status.hasProfile = true
            status.hasBankAccount = !profile.bankConnections.isEmpty
        }
        status.hasSeries = !((try? stores.series.all()) ?? []).isEmpty
        status.hasRates = (try? stores.rates.latestDay(for: .eur)) != nil
        return status
    }
}
