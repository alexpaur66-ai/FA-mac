// Overview (screens-flows.md §2a, lean pass other-01..04, other-15): the two tiles for today, the
// "Needs attention" queue, then the month with its two tiles; the Getting started card while setup is
// incomplete (§2j). Everything is computed from the live document states.

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
    /// The Overdue tile: Unpaid sorted by due date, oldest first (screens-flows.md §2a).
    let showOverdue: @MainActor () -> Void
    let newDocument: @MainActor (DocumentKind) -> Void
    /// ↩ on a queue row: Record Payment… for an overdue document, Create Tax Document for a payment
    /// without one (other-03). False when the row has no action, so ↩ is not swallowed.
    let runQueueAction: @MainActor (OverviewFigures.QueueItem.Kind, String) -> Bool
    /// The backup row's Back Up Now (§2a, §2h); nil for the in-memory database, which shows no backup row.
    let backUpNow: (@MainActor () -> Void)?
    /// The Getting started card's "Moving from another Mac? Restore from Backup…" (§2j); nil for the
    /// in-memory database.
    let restoreFromBackup: (@MainActor () -> Void)?

    @State private var month: CalendarDay
    /// Nil until the first load, so a set-up database never shows the card for a moment.
    @State private var setup: SetupStatus?
    /// The selected queue row, by item: a document in two groups (overdue, and its tax document missing)
    /// selects the row that was clicked, not both.
    @State private var selectedQueueItem: String?
    @FocusState private var queueFocused: Bool
    /// Per advance in the queue's "tax document missing" group: the received money without an issued tax
    /// document. The states carry only the paid total, which also counts the payments already documented.
    @State private var untaxedReceived: [String: Money] = [:]
    @AppStorage(SettingsPane.storageKey) private var settingsPane: SettingsPane = .general
    @AppStorage(BackupSettings.lastSuccessKey) private var backupLastSuccess: Double = 0
    @AppStorage(BackupSettings.lastFailureKey) private var backupFailure: String = ""
    @Environment(\.openSettings) private var openSettings
    @Environment(\.locale) private var locale

    init(stores: Stores, documents: DocumentListModel, selection: Binding<String?>, forced: Binding<Bool>,
         show: @escaping @MainActor (SidebarItem) -> Void, showOverdue: @escaping @MainActor () -> Void,
         newDocument: @escaping @MainActor (DocumentKind) -> Void,
         runQueueAction: @escaping @MainActor (OverviewFigures.QueueItem.Kind, String) -> Bool,
         backUpNow: (@MainActor () -> Void)? = nil, restoreFromBackup: (@MainActor () -> Void)? = nil) {
        self.stores = stores
        self.documents = documents
        self._selection = selection
        self._forced = forced
        self.show = show
        self.showOverdue = showOverdue
        self.newDocument = newDocument
        self.runQueueAction = runQueueAction
        self.backUpNow = backUpNow
        self.restoreFromBackup = restoreFromBackup
        _month = State(initialValue: CalendarDay(Date(), in: .current).startOfMonth)
    }

    var body: some View {
        let figures = OverviewFigures(states: documents.states, month: month, today: documents.today)
        let placeholder = documents.loaded ? RedactionReasons() : RedactionReasons.placeholder
        let setupIncomplete = setup.map { !$0.isComplete } ?? false
        let noDocuments = documents.loaded && documents.states.isEmpty
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    // One state at a time (other-15): the data error wins over everything, the card included.
                    if let error = documents.error {
                        dataError(error)
                    } else {
                        if let setup, setupIncomplete || forced {
                            gettingStarted(setup)
                        }
                        if setupIncomplete && noDocuments {
                            // First run: the card alone.
                            EmptyView()
                        } else if noDocuments {
                            // Undecided until the setup check ran, so a first run never shows this for a moment.
                            if setup != nil {
                                noDocumentsView
                            }
                        } else {
                            // Placeholder tiles until the first states arrive (screens-flows.md §2a, Loading).
                            todayTiles(figures).redacted(reason: placeholder)
                            queue(figures).redacted(reason: placeholder)
                            monthBar
                            monthTiles(figures).redacted(reason: placeholder)
                        }
                    }
                }
                .padding(Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // ↑↓ in the queue keep the selected row visible; without an anchor it scrolls only when needed.
            .onChange(of: selectedQueueItem) { _, id in
                if let id { proxy.scrollTo(id) }
            }
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
            // One plain New Invoice button and no search (design-system.md §8.11); ⇧⌘N makes an advance.
            ToolbarItem {
                Button { newDocument(.invoice) } label: {
                    Label { Text(L.newInvoice) } icon: { Image(systemName: "plus") }
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

    // MARK: Getting started (screens-flows.md §2j, other-04)

    /// Three steps and one button that opens the first unfinished pane. Shown again by Help ▸ Getting
    /// Started once everything is done: all ✓, with a close button and without Open Settings….
    private func gettingStarted(_ setup: SetupStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            // First run only: a card Help ▸ Getting Started brings back with every step done has no link.
            if !setup.isComplete, let restoreFromBackup {
                Button { restoreFromBackup() } label: { Text(L.restoreMovingFromAnotherMac) }
                    .buttonStyle(.link)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(L.gettingStarted).textRole(.sectionTitle)
                Spacer()
                if setup.isComplete {
                    Button { forced = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(L.close))
                        .help(Text(L.close))
                }
            }
            Text(L.setupIntro).textRole(.body)
            step(done: setup.hasProfile, title: L.stepCompany)
            step(done: setup.hasBankAccount, title: L.stepBank)
            step(done: setup.hasSeries, title: L.stepSeries)
            if let pane = setup.firstUnfinishedPane {
                Button { open(pane) } label: { Text(L.openSettings) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface()
    }

    /// One step: the state as symbol + word for VoiceOver (design-system.md §4.3) and the title.
    private func step(done: Bool, title: LocalizedStringResource) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)
            Text(title).textRole(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(done ? L.done : L.notDone))
    }

    /// Opens Settings on the step's pane (screens-flows.md §2j): the pane is stored first, the window reads it.
    private func open(_ pane: SettingsPane) {
        settingsPane = pane
        openSettings()
    }

    // MARK: Tiles (other-02)

    /// Unpaid and Overdue: the open balances of invoices and final invoices today.
    private func todayTiles(_ figures: OverviewFigures) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Spacing.xxl, alignment: .top)],
                  alignment: .leading, spacing: Spacing.xxl) {
            Tile(title: L.tileUnpaid, action: { show(.filter(.unpaid)) }) {
                KPIMoney(monies: figures.unpaid, locale: locale)
            } lines: {
                Text(verbatim: Count.documents(figures.unpaidCount)).textRole(.rowSecondary)
            } footer: {
                // Its own button, never inside the tile's: it opens Documents ▸ Open advances.
                if figures.unpaidAdvancesCount > 0 {
                    Button { show(.filter(.openAdvances)) } label: {
                        Text(unpaidAdvancesLine(figures)).textRole(.rowSecondary).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            Tile(title: L.tileOverdue, action: { showOverdue() }) {
                KPIMoney(monies: figures.overdue, locale: locale)
            } lines: {
                if figures.overdueCount > 0 {
                    let oldest = figures.oldestOverdueDays == 1 ? L.oldestOverdueOne : L.oldestOverdue(figures.oldestOverdueDays)
                    Text(L.overdueTileLine(Count.documents(figures.overdueCount), String(localized: oldest)))
                        .textRole(.rowSecondary)
                }
            }
        }
    }

    /// "Unpaid advances: 2 · 3 000,00 € · 1 overdue": one sentence; the overdue part only above 0.
    private func unpaidAdvancesLine(_ figures: OverviewFigures) -> LocalizedStringResource {
        let amounts = figures.unpaidAdvances
            .map { MoneyText.format($0.amount, currency: $0.currency.code, locale: locale) }
            .joined(separator: " + ")
        if figures.overdueAdvancesCount > 0 {
            return L.unpaidAdvancesLineOverdue(figures.unpaidAdvancesCount, amounts, figures.overdueAdvancesCount)
        }
        return L.unpaidAdvancesLine(figures.unpaidAdvancesCount, amounts)
    }

    private var monthBar: some View {
        HStack(spacing: Spacing.m) {
            Button { month = month.adding(months: -1).startOfMonth } label: {
                Label { Text(L.previousMonth) } icon: { Image(systemName: "chevron.left") }
            }
            .labelStyle(.iconOnly)
            .help(Text(L.previousMonth))
            Text(verbatim: monthAndYear(month)).textRole(.screenTitle).frame(minWidth: 160)
            Button { month = month.adding(months: 1).startOfMonth } label: {
                Label { Text(L.nextMonth) } icon: { Image(systemName: "chevron.right") }
            }
            .labelStyle(.iconOnly)
            .help(Text(L.nextMonth))
        }
    }

    private func monthAndYear(_ day: CalendarDay) -> String {
        day.midnight(in: .current).formatted(Date.FormatStyle(locale: locale).month(.wide).year())
    }

    private func monthOnly(_ day: CalendarDay) -> String {
        day.midnight(in: .current).formatted(Date.FormatStyle(locale: locale).month(.wide))
    }

    /// Issued in ‹month› (the revenue from tax documents by issue date) and VAT by DUZP; neither is a button,
    /// because no list is filtered to a month.
    private func monthTiles(_ figures: OverviewFigures) -> some View {
        let name = monthOnly(month)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Spacing.xxl, alignment: .top)],
                         alignment: .leading, spacing: Spacing.xxl) {
            Tile(title: L.tileIssued(name), action: nil) {
                KPIMoney(monies: figures.revenue, locale: locale)
            } lines: {
                if figures.issuedTotal > 0 {
                    Text(verbatim: Count.documents(figures.issuedTotal)).textRole(.rowSecondary)
                }
            }
            Tile(title: L.tileVAT(name), action: nil) {
                MoneyText(amount: figures.vatCZK, currency: "CZK", locale: locale, role: .kpi)
            } lines: {
                EmptyView()
            }
        }
    }

    // MARK: Queue (other-03)

    /// A keyboard list: ↑↓ select, ↩ runs the selected row's action; no other key acts. Selecting a row
    /// shows its document in the detail column, so ⌘R and the Document menu work on it.
    private func queue(_ figures: OverviewFigures) -> some View {
        let backupText = backUpNow == nil ? nil
            : BackupStatus.queueText(lastSuccess: backupLastSuccess, failure: backupFailure)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.needsAttention).textRole(.sectionTitle)
            if figures.queue.isEmpty && backupText == nil {
                Label {
                    Text(L.allCaughtUp)
                } icon: {
                    Image(systemName: "checkmark.circle").foregroundStyle(Color.secondary)
                }
                .textRole(.body)
            } else if !figures.queue.isEmpty {
                let current = currentQueueItem(in: figures.queue)?.id
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(figures.queue) { item in
                        let selected = current == item.id
                        QueueRow(item: item, amount: amount(of: item), selected: selected, focused: queueFocused)
                            .id(item.id)
                            .onTapGesture {
                                select(item)
                                queueFocused = true
                            }
                            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
                            .accessibilityAction { select(item) }
                    }
                }
                .focusable()
                // The selected row shows the focus in the accent colour; no ring around the whole queue.
                .focusEffectDisabled()
                .focused($queueFocused)
                .onKeyPress(.downArrow) {
                    move(by: 1, in: figures.queue)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(by: -1, in: figures.queue)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let item = currentQueueItem(in: figures.queue) else { return .ignored }
                    return runQueueAction(item.kind, item.state.id) ? .handled : .ignored
                }
            }
            // The backup group comes last (§2a). It is its own row with a button rather than a row of the
            // keyboard list above, whose selection is a document's.
            if let backupText, let backUpNow {
                BackupQueueRow(text: backupText, backUpNow: backUpNow)
            }
        }
    }

    /// The selected queue row, derived from the selected document: the row that was clicked while it still
    /// shows that document, else the document's first row (a restored selection, or one made elsewhere).
    private func currentQueueItem(in items: [OverviewFigures.QueueItem]) -> OverviewFigures.QueueItem? {
        guard let selection else { return nil }
        if let selectedQueueItem, let clicked = items.first(where: { $0.id == selectedQueueItem }),
           clicked.state.id == selection {
            return clicked
        }
        return items.first { $0.state.id == selection }
    }

    private func select(_ item: OverviewFigures.QueueItem) {
        selectedQueueItem = item.id
        selection = item.state.id
    }

    private func move(by step: Int, in items: [OverviewFigures.QueueItem]) {
        guard !items.isEmpty else { return }
        let currentID = currentQueueItem(in: items)?.id
        let current = items.firstIndex { $0.id == currentID }
        let next: Int
        if let current {
            next = min(max(current + step, 0), items.count - 1)
        } else {
            next = step > 0 ? 0 : items.count - 1
        }
        select(items[next])
    }

    /// The row's amount; for a missing tax document the received money without one, once loaded.
    private func amount(of item: OverviewFigures.QueueItem) -> Money? {
        if item.kind == .taxDocumentMissing, let untaxed = untaxedReceived[item.state.id] {
            return untaxed
        }
        return item.amount
    }

    // MARK: States (other-15)

    /// The observation stopped (screens-flows.md §2a, Error): the banner alone, with the text, Try Again,
    /// the data folder and Restore from Backup… (disabled until backups exist). The icon is orange: red is
    /// only for Overdue.
    private func dataError(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label {
                Text(L.dbCannotOpen).textRole(.sectionTitle)
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(StatusTone.caution.tint)
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

    /// Setup complete and no document yet (screens-flows.md §2a, Empty).
    private var noDocumentsView: some View {
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

/// One tile: a text label, the figure in the KPI role and its secondary lines, as one VoiceOver element.
/// Clicking opens the matching list; a tile without an action is not a button. The footer sits inside the
/// tile but outside its button (the Unpaid advances link).
private struct Tile<Value: View, Lines: View, Footer: View>: View {
    let title: LocalizedStringResource
    let action: (@MainActor () -> Void)?
    let value: Value
    let lines: Lines
    let footer: Footer

    init(title: LocalizedStringResource, action: (@MainActor () -> Void)?,
         @ViewBuilder value: () -> Value, @ViewBuilder lines: () -> Lines, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.action = action
        self.value = value()
        self.lines = lines()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let action {
                Button(action: action) { main }
                    .buttonStyle(.plain)
            } else {
                main
            }
            footer
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface()
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).textRole(.label)
            value
            lines
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension Tile where Footer == EmptyView {
    init(title: LocalizedStringResource, action: (@MainActor () -> Void)?,
         @ViewBuilder value: () -> Value, @ViewBuilder lines: () -> Lines) {
        self.init(title: title, action: action, value: value, lines: lines, footer: { EmptyView() })
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

/// "Backup failed: ‹reason›", "No backup yet" or "Last backup 9 days ago", with Back Up Now (§2a).
private struct BackupQueueRow: View {
    let text: String
    let backUpNow: @MainActor () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(StatusTone.caution.tint)
                .accessibilityHidden(true)
            Text(verbatim: text).textRole(.body)
            Spacer()
            Button { backUpNow() } label: { Text(L.backUpNow) }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }
}

private struct QueueRow: View {
    let item: OverviewFigures.QueueItem
    let amount: Money?
    let selected: Bool
    /// The list has keyboard focus: the selection shows in the accent colour, else in the inactive grey.
    let focused: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        let summary = item.state.summary
        HStack(spacing: Spacing.m) {
            Image(systemName: item.symbol)
                .foregroundStyle(item.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(L.numberAndClient(summary.number ?? String(localized: L.draftTitle), summary.customerName))
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
        .background(background, in: RoundedRectangle(cornerRadius: Radius.m))
        .contentShape(RoundedRectangle(cornerRadius: Radius.m))
        .accessibilityElement(children: .combine)
    }

    private var background: AnyShapeStyle {
        guard selected else { return AnyShapeStyle(Color.clear) }
        return focused ? AnyShapeStyle(SelectionShapeStyle()) : AnyShapeStyle(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
    }
}

/// The figures of the Overview, computed from the states by the aggregation rules of screens-flows.md §2a.
struct OverviewFigures {
    struct QueueItem: Identifiable, Hashable {
        /// The v0.1 groups (other-03); a stale draft is not queued (the sidebar's Drafts badge counts drafts).
        enum Kind: Hashable {
            case overdue, taxDocumentMissing
        }

        let kind: Kind
        let state: DocumentState

        var id: String { state.id + "/" + String(describing: kind) }

        /// The amount the row shows: the open balance of an overdue document, or the received money (the
        /// Overview replaces it by the part without a tax document once the payments are loaded).
        var amount: Money? {
            switch kind {
            case .overdue: state.outstanding
            case .taxDocumentMissing: state.paid
            }
        }

        var symbol: String {
            switch kind {
            case .overdue: "exclamationmark.circle.fill"
            case .taxDocumentMissing: "checkmark.circle.trianglebadge.exclamationmark"
            }
        }

        /// The tone of the matching status (design-system.md §4.3): red only for Overdue.
        var tint: Color {
            switch kind {
            case .overdue: DocumentStateLabel.overdue.style.tone.tint
            case .taxDocumentMissing: DocumentStateLabel.paidTaxDocumentMissing.style.tone.tint
            }
        }

        var detail: String {
            switch kind {
            case .overdue: Count.daysOverdue(state.daysOverdue)
            case .taxDocumentMissing: String(localized: L.queueTaxDocumentMissing)
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
        var overdueItems: [QueueItem] = [], taxItems: [QueueItem] = []

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
}

/// The setup steps (screens-flows.md §2j, other-04): company profile, bank account and number series.
struct SetupStatus: Equatable {
    /// The user default Help ▸ Getting Started sets, so the card shows again once it has hidden itself.
    static let forcedKey = "gettingStartedForced"

    var hasProfile = false
    var hasBankAccount = false
    /// The number series are confirmed: Settings ▸ Numbering was saved, or a series already issued (set-09).
    var hasSeries = false

    /// Company, bank account and series; rates are typed per document and never block (decision of 5 Nov 2026).
    var isComplete: Bool { hasProfile && hasBankAccount && hasSeries }

    /// Open Settings… opens the first unfinished pane: Company, then Bank accounts, then Numbering.
    var firstUnfinishedPane: SettingsPane? {
        if !hasProfile { return .company }
        if !hasBankAccount { return .bank }
        if !hasSeries { return .numbering }
        return nil
    }

    static func load(_ stores: Stores) -> SetupStatus {
        var status = SetupStatus()
        if let profile = try? stores.profile.load() {
            status.hasProfile = true
            status.hasBankAccount = !profile.bankConnections.isEmpty
        }
        status.hasSeries = (try? stores.series.isNumberingConfirmed()) ?? false
        return status
    }
}
