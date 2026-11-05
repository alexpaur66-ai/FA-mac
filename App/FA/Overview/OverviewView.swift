// Overview (screens-flows.md §2a): the month bar, four tiles, the attention queue, and the
// Getting started card on a fresh database (§2j). Everything is computed from the live document states.

import AppKit
import Combine
import InvoicingCore
import InvoicingData
import SwiftUI

struct OverviewView: View {
    let stores: Stores
    let documents: DocumentListModel
    @Binding var selection: String?
    /// Help ▸ Getting Started: the card stays up although the required steps are done, until it is closed.
    @Binding var forced: Bool
    let show: @MainActor (SidebarItem) -> Void
    let newDocument: @MainActor (DocumentKind) -> Void
    let newClient: @MainActor () -> Void
    let importRates: @MainActor () -> Void

    @State private var month: CalendarDay
    /// Nil until the first load, so a set-up database never shows the card for a moment.
    @State private var setup: SetupStatus?
    /// The highlighted queue row, by item: a document in two groups (overdue, and its tax document
    /// missing) highlights the row that was clicked, not both.
    @State private var selectedQueueItem: String?
    /// Per advance in the queue's "tax document missing" group: the received money without an issued tax
    /// document. The states carry only the paid total, which also counts the payments already documented.
    @State private var untaxedReceived: [String: Money] = [:]
    @AppStorage(SettingsPane.storageKey) private var settingsPane: SettingsPane = .general
    @Environment(\.openSettings) private var openSettings
    @Environment(\.locale) private var locale

    init(stores: Stores, documents: DocumentListModel, selection: Binding<String?>, forced: Binding<Bool>,
         show: @escaping @MainActor (SidebarItem) -> Void, newDocument: @escaping @MainActor (DocumentKind) -> Void,
         newClient: @escaping @MainActor () -> Void, importRates: @escaping @MainActor () -> Void) {
        self.stores = stores
        self.documents = documents
        self._selection = selection
        self._forced = forced
        self.show = show
        self.newDocument = newDocument
        self.newClient = newClient
        self.importRates = importRates
        _month = State(initialValue: CalendarDay(Date(), in: .current).startOfMonth)
    }

    var body: some View {
        let figures = OverviewFigures(states: documents.states, month: month, today: documents.today)
        let placeholder = documents.loaded ? RedactionReasons() : RedactionReasons.placeholder
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                if let setup, forced || !setup.isComplete {
                    gettingStarted(setup)
                }
                if let error = documents.error {
                    dataError(error)
                } else if documents.loaded && documents.states.isEmpty {
                    noDocuments
                } else {
                    monthBar
                    // Placeholder tiles until the first states arrive (screens-flows.md §2a, Loading).
                    tiles(figures).redacted(reason: placeholder)
                    queue(figures).redacted(reason: placeholder)
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(L.overview))
        .task(id: documents.states) {
            reloadSetup()
            reloadUntaxedReceived()
        }
        // Saving the company, a bank account or a series in the Settings window changes no document
        // state, so the steps reload when the main window becomes key again.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification).receive(on: RunLoop.main)) { _ in
            reloadSetup()
        }
        .onChange(of: selection) { _, newValue in
            if newValue == nil { selectedQueueItem = nil }
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
                .help(Text(L.newInvoiceHelp))
            }
        }
    }

    private func reloadSetup() {
        setup = SetupStatus.load(stores)
    }

    /// The payments of each queued advance whose tax document is not issued yet (the store's
    /// `missingReceipts` rule: money received or credited without an issued receipt), summed.
    private func reloadUntaxedReceived() {
        var amounts: [String: Money] = [:]
        for state in documents.states where state.summary.kind == .advanceRequest && state.summary.status == .issued
            && state.taxDocumentRequired && !state.taxDocumentIssued {
            guard let payments = try? stores.documents.payments(for: state.id) else { continue }
            let untaxed = payments.filter { $0.isIncoming && !$0.receiptIssued }.map(\.amount)
            if let sum = MoneyList.sums(untaxed).first {
                amounts[state.id] = sum
            }
        }
        untaxedReceived = amounts
    }

    // MARK: Getting started (screens-flows.md §2j)

    private func gettingStarted(_ setup: SetupStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.gettingStarted).textRole(.sectionTitle)
                Spacer()
                if setup.isComplete {
                    // Shown again by Help ▸ Getting Started: the close button puts it away.
                    Button { forced = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(L.close))
                        .help(Text(L.close))
                }
            }
            Text(L.setupIntro).textRole(.body)
            step(done: setup.hasProfile, title: L.stepCompany) {
                Button { open(.company) } label: { Text(L.openSettings) }
            }
            step(done: setup.hasBankAccount, title: L.stepBank) {
                Button { open(.bank) } label: { Text(L.openSettings) }
            }
            step(done: setup.hasSeries, title: L.stepSeries) {
                Button { open(.numbering) } label: { Text(L.openSettings) }
            }
            // Optional: rates are typed per document (decision of 5 Nov 2026); the import fills the table.
            step(done: setup.hasRates, title: L.stepRates, actionsStay: true) {
                Button { importRates() } label: { Text(L.importRates) }
            }
            step(done: setup.hasClient || !documents.states.isEmpty, title: L.stepFirstDocuments, actionsStay: true) {
                Button { newClient() } label: { Text(L.newClient) }
                Button { newDocument(.invoice) } label: { Text(L.newInvoice) }
            }
        }
        .padding(Spacing.l)
        .tileSurface()
    }

    /// One step: the state as symbol + word for VoiceOver (design-system.md §4.3), the title, and its
    /// buttons. The buttons of a required step go once it is done; an optional step keeps them.
    private func step<Actions: View>(done: Bool, title: LocalizedStringResource, actionsStay: Bool = false,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.green : Color.secondary)
                    .accessibilityHidden(true)
                Text(title).textRole(.body)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(done ? L.done : L.notDone))
            Spacer()
            if !done || actionsStay {
                actions()
            }
        }
    }

    /// Opens Settings on the step's pane (screens-flows.md §2j): the pane is stored first, the window reads it.
    private func open(_ pane: SettingsPane) {
        settingsPane = pane
        openSettings()
    }

    // MARK: Month and tiles

    private var monthBar: some View {
        HStack(spacing: Spacing.m) {
            Button { month = month.adding(months: -1).startOfMonth } label: {
                Label { Text(L.previousMonth) } icon: { Image(systemName: "chevron.left") }
            }
            .labelStyle(.iconOnly)
            .help(Text(L.previousMonth))
            Text(verbatim: monthName(month)).textRole(.screenTitle).frame(minWidth: 160)
            Button { month = month.adding(months: 1).startOfMonth } label: {
                Label { Text(L.nextMonth) } icon: { Image(systemName: "chevron.right") }
            }
            .labelStyle(.iconOnly)
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
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Spacing.xxl, alignment: .top)],
                         alignment: .leading, spacing: Spacing.xxl) {
            Tile(symbol: "clock", title: L.tileUnpaid, action: { show(.filter(.unpaid)) }) {
                KPIMoney(monies: figures.unpaid, locale: locale)
            } lines: {
                Text(verbatim: Count.documents(figures.unpaidCount)).textRole(.rowSecondary)
                HStack(spacing: Spacing.xs) {
                    Text(L.unpaidAdvancesCount(figures.unpaidAdvancesCount)).textRole(.rowSecondary)
                    MoneyListText(monies: figures.unpaidAdvances, locale: locale, role: .amountSecondary)
                }
            }
            Tile(symbol: "exclamationmark.circle", title: L.tileOverdue, action: { show(.filter(.overdue)) }) {
                KPIMoney(monies: figures.overdue, locale: locale)
            } lines: {
                HStack(spacing: Spacing.xs) {
                    Text(verbatim: Count.documents(figures.overdueCount)).textRole(.rowSecondary)
                    if figures.oldestOverdueDays > 0 {
                        Text(verbatim: "·").textRole(.rowSecondary).accessibilityHidden(true)
                        Text(figures.oldestOverdueDays == 1 ? L.oldestOverdueOne : L.oldestOverdue(figures.oldestOverdueDays))
                            .textRole(.rowSecondary)
                    }
                }
                Text(L.overdueAdvancesCount(figures.overdueAdvancesCount)).textRole(.rowSecondary)
            }
            Tile(symbol: Symbols.document, title: L.tileIssued(name), action: issuedAction) {
                Text(verbatim: String(figures.issuedTotal)).textRole(.kpi)
            } lines: {
                Text(verbatim: figures.issuedCountsText).textRole(.rowSecondary)
                HStack(spacing: Spacing.xs) {
                    Text(L.revenueTaxDocuments).textRole(.rowSecondary)
                    MoneyListText(monies: figures.revenue, locale: locale, role: .amountSecondary)
                }
            }
            // By tax point, not by issue date, so no document filter matches it; the tile opens nothing.
            Tile(symbol: "percent", title: L.tileVAT(name), action: nil) {
                MoneyText(amount: figures.vatCZK, currency: "CZK", locale: locale, role: .kpi)
            } lines: {
                Text(L.vatTileNote).textRole(.rowSecondary)
            }
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
                let selected = selectedQueueItem == item.id
                Button {
                    selectedQueueItem = item.id
                    selection = item.state.id
                } label: {
                    QueueRow(item: item, amount: amount(of: item), selected: selected)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
            }
        }
    }

    /// The row's amount; for a missing tax document the received money without one, once loaded.
    private func amount(of item: OverviewFigures.QueueItem) -> Money? {
        if item.kind == .taxDocumentMissing, let untaxed = untaxedReceived[item.state.id] {
            return untaxed
        }
        return item.amount
    }

    // MARK: States

    /// The observation stopped (screens-flows.md §2a, Error): the banner with the text, Try again, the data
    /// folder, and Restore from Backup… (disabled until backups exist).
    private func dataError(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label {
                Text(L.dbCannotOpen).textRole(.sectionTitle)
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(.red)
            }
            Text(verbatim: error)
                .textRole(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.m) {
                Button { documents.restart() } label: { Text(L.retry) }
                if let url = stores.databaseURL {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Text(L.showDataFolder) }
                }
                Button {} label: { Text(L.restoreFromBackup) }
                    .disabled(true)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface()
    }

    /// First run (screens-flows.md §2a, Empty): under the Getting started card, instead of empty tiles.
    private var noDocuments: some View {
        ContentUnavailableView {
            Label { Text(L.noDocuments) } icon: { Image(systemName: Symbols.document) }
        } description: {
            Text(L.noDocumentsDescription)
        } actions: {
            Button { newDocument(.invoice) } label: { Text(L.newInvoice) }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// One number tile: symbol, label, the figure in the KPI role and up to two secondary lines. Clicking opens
/// the matching filter; a tile without an action is not a button.
private struct Tile<Value: View, Lines: View>: View {
    let symbol: String
    let title: LocalizedStringResource
    let action: (@MainActor () -> Void)?
    let value: Value
    let lines: Lines

    init(symbol: String, title: LocalizedStringResource, action: (@MainActor () -> Void)?,
         @ViewBuilder value: () -> Value, @ViewBuilder lines: () -> Lines) {
        self.symbol = symbol
        self.title = title
        self.action = action
        self.value = value()
        self.lines = lines()
    }

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
            value
            lines
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface()
    }
}

/// The tile figure: one KPI amount per currency, never summed across currencies (screens-flows.md §2a).
private struct KPIMoney: View {
    let monies: [Money]
    let locale: Locale

    var body: some View {
        let sums = MoneyList.sums(monies)
        if sums.isEmpty {
            Text(verbatim: "—").textRole(.kpi)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(Array(sums.enumerated()), id: \.offset) { _, money in
                    MoneyText(amount: money.amount, currency: money.currency.code, locale: locale, role: .kpi)
                }
            }
        }
    }
}

private struct QueueRow: View {
    let item: OverviewFigures.QueueItem
    let amount: Money?
    let selected: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        let summary = item.state.summary
        HStack(spacing: Spacing.m) {
            Image(systemName: item.symbol)
                .foregroundStyle(item.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: [summary.number ?? String(localized: L.draftTitle), summary.customerName]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .textRole(.body)
                Text(verbatim: item.detail).textRole(.rowSecondary)
            }
            Spacer()
            if let amount {
                MoneyText(amount: amount.amount, currency: amount.currency.code, locale: locale)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(selected ? AnyShapeStyle(SelectionShapeStyle()) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: Radius.m))
        .contentShape(RoundedRectangle(cornerRadius: Radius.m))
        .accessibilityElement(children: .combine)
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

        /// The amount the row shows: the open balance of an overdue document, the received money (the
        /// Overview replaces it by the part without a tax document once the payments are loaded), or a
        /// draft's total. Nil for a draft whose totals cannot be computed yet.
        var amount: Money? {
            switch kind {
            case .overdue: state.outstanding
            case .taxDocumentMissing: state.paid
            case .oldDraft: state.summary.totalGross
            }
        }

        var symbol: String {
            switch kind {
            case .overdue: "exclamationmark.circle.fill"
            case .taxDocumentMissing: "checkmark.circle.trianglebadge.exclamationmark"
            case .oldDraft: "pencil.circle"
            }
        }

        /// The tone of the matching status (design-system.md §4.3): a stale draft stays neutral.
        var tint: Color {
            switch kind {
            case .overdue: DocumentStateLabel.overdue.style.tone.tint
            case .taxDocumentMissing: DocumentStateLabel.paidTaxDocumentMissing.style.tone.tint
            case .oldDraft: DocumentStateLabel.draft.style.tone.tint
            }
        }

        var detail: String {
            switch kind {
            case .overdue: Count.daysOverdue(state.daysOverdue)
            case .taxDocumentMissing: String(localized: L.queueTaxDocumentMissing)
            case .oldDraft: String(localized: L.queueOldDraft)
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
            let open = state.settlement == .open || state.settlement == .partlyPaid
            if summary.status == .issued {
                if state.countsAsUnpaidInvoice {
                    unpaid.append(state.outstanding)
                    unpaidCount += 1
                    if state.isOverdue {
                        overdue.append(state.outstanding)
                        overdueCount += 1
                        oldest = max(oldest, state.daysOverdue)
                    }
                }
                if state.isOpenAdvance && open {
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
    /// counted twice (§2a). `amountDue` is the supply's gross minus the deducted advances and minus the
    /// advances paid on § 64 goods, which had no tax document and so count here (ADR 0012).
    static func revenueAmount(_ summary: DocumentSummary) -> Money? {
        guard summary.kind.isTaxDocument else { return nil }
        guard summary.kind == .finalInvoice else { return summary.totalGross }
        if let due = summary.amountDue, let paid = summary.paidInAdvance, paid.currency == due.currency {
            return due + paid
        }
        return summary.amountDue
    }

    /// The overdue group of the queue: every overdue document except an advance an issued final invoice
    /// already deducted (§2a never counts it as overdue).
    static func queuesAsOverdue(_ state: DocumentState) -> Bool {
        state.isOverdue && !(state.summary.kind == .advanceRequest && state.deductedInFinal)
    }

    /// Every document issued in the month, all types together.
    var issuedTotal: Int {
        issuedCounts.values.reduce(0, +)
    }

    /// "Invoice 6 · Advance 2 · Tax doc (payment) 1", or "0".
    var issuedCountsText: String {
        let parts = DocumentKind.allCases.compactMap { kind -> String? in
            guard let count = issuedCounts[kind], count > 0 else { return nil }
            return String(localized: kind.shortTitle) + " " + String(count)
        }
        return parts.isEmpty ? "0" : parts.joined(separator: " · ")
    }
}

/// The setup steps (screens-flows.md §2j): three required, the rates and the first client optional.
struct SetupStatus: Equatable {
    /// The user default Help ▸ Getting Started sets, so the card shows again once it has hidden itself.
    static let forcedKey = "gettingStartedForced"

    var hasProfile = false
    var hasBankAccount = false
    var hasSeries = false
    var hasRates = false
    var hasClient = false

    /// Company, bank account and series; rates are typed per document and never block (decision of 5 Nov 2026).
    var isComplete: Bool { hasProfile && hasBankAccount && hasSeries }

    static func load(_ stores: Stores) -> SetupStatus {
        var status = SetupStatus()
        if let profile = try? stores.profile.load() {
            status.hasProfile = true
            status.hasBankAccount = !profile.bankConnections.isEmpty
        }
        status.hasSeries = !((try? stores.series.all()) ?? []).isEmpty
        status.hasRates = (try? stores.rates.latestDay(for: .eur)) != nil
        status.hasClient = !((try? stores.customers.all()) ?? []).isEmpty
        return status
    }
}
