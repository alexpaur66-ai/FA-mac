// The Documents section: one table over the live document states, with the smart filter from the sidebar,
// search, the per-filter sort and the toolbar (screens-flows.md §2b).

import InvoicingCore
import InvoicingData
import SwiftUI

struct DocumentsView: View {
    let stores: Stores
    let documents: DocumentListModel
    let filter: DocumentSmartFilter
    @Binding var selection: Set<String>
    @Binding var inspectorPresented: Bool
    /// An inline result or error line from the last action; stays until the next action (never time-boxed).
    let resultLine: String?
    let newDocument: @MainActor (DocumentKind) -> Void
    let recordPayment: @MainActor (String) -> Void
    let deleteDraft: @MainActor (String) -> Void

    @State private var search = ""
    @State private var sortOrder: [KeyPathComparator<DocumentRow>] = [KeyPathComparator(\DocumentRow.issueDate, order: .reverse)]
    @SceneStorage("documentsColumns") private var columnCustomization: TableColumnCustomization<DocumentRow>
    @Environment(\.locale) private var locale

    private var rows: [DocumentRow] {
        documents.rows(for: filter)
            .filter { $0.matches(search: search) }
            .sorted(using: sortOrder)
    }

    /// The one issued document selected, for Record Payment.
    private var singleIssued: String? {
        guard selection.count == 1, let id = selection.first, let state = documents.state(id: id),
              state.summary.status == .issued, state.summary.kind != .paymentTaxDocument,
              state.closure?.kind != .closedUnpaid else { return nil }
        return id
    }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            if documents.loaded && rows.isEmpty {
                emptyState
            } else {
                table(rows)
            }
            if let resultLine {
                Divider()
                Text(verbatim: resultLine)
                    .textRole(.caption)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !selection.isEmpty {
                Divider()
                selectionBar(rows.filter { selection.contains($0.id) })
            }
        }
        .navigationTitle(Text(L.documents))
        .navigationSubtitle(Text(verbatim: String(localized: filter.title) + " · " + String(rows.count)))
        .searchable(text: $search, placement: .toolbar)
        .onChange(of: filter, initial: true) { _, newFilter in
            sortOrder = newFilter.defaultSortOrder
        }
        .toolbar { toolbar }
    }

    private func table(_ rows: [DocumentRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn(Text(L.colStatus)) { row in
                StatusBadge(row.badgeInputs, detail: row.badgeDetail(locale: locale))
            }
            .width(min: 110, ideal: 190)
            .customizationID("status")

            TableColumn(Text(L.colNumber), value: \.number) { row in
                Text(verbatim: row.number.isEmpty ? "—" : row.number).textRole(.body)
            }
            .width(min: 90, ideal: 130)
            .customizationID("number")

            TableColumn(Text(L.colType), value: \.typeName) { row in
                Label { Text(verbatim: row.typeName) } icon: { Image(systemName: row.kind.symbol) }
                    .textRole(.body)
            }
            .width(min: 80, ideal: 110)
            .customizationID("type")

            TableColumn(Text(L.colClient), value: \.customerName) { row in
                Text(verbatim: row.customerName.isEmpty ? String(localized: L.noClient) : row.customerName)
                    .textRole(.body)
                    .truncationMode(.middle)
            }
            .customizationID("client")

            TableColumn(Text(L.colIssued), value: \.issueDate) { row in
                DayText(row.issueDate)
                    .foregroundStyle(row.isDraft ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
            }
            .width(min: 90, ideal: 100)
            .alignment(.trailing)
            .customizationID("issued")

            TableColumn(Text(L.colDue), value: \.dueDate) { row in
                DayText(row.dueDate)
            }
            .width(min: 90, ideal: 100)
            .alignment(.trailing)
            .customizationID("due")

            TableColumn(Text(L.colTotal), value: \.total) { row in
                MoneyText(amount: row.total, currency: row.currencyCode, locale: locale)
            }
            .width(min: 100, ideal: 130)
            .alignment(.trailing)
            .customizationID("total")

            TableColumn(Text(L.colOpen), value: \.outstanding) { row in
                MoneyText(amount: row.outstanding, currency: row.currencyCode, locale: locale)
            }
            .width(min: 100, ideal: 130)
            .alignment(.trailing)
            .customizationID("open")

            TableColumn(Text(L.colVS), value: \.variableSymbol)
                .customizationID("vs")
                .defaultVisibility(.hidden)

            TableColumn(Text(L.colCurrency), value: \.currencyCode)
                .customizationID("currency")
                .defaultVisibility(.hidden)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(ids)
        }
        .onDeleteCommand {
            for id in selection where documents.state(id: id)?.summary.status == .draft {
                deleteDraft(id)
            }
        }
    }

    @ViewBuilder private func contextMenu(_ ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first, let state = documents.state(id: id) {
            if state.summary.status == .issued && state.summary.kind != .paymentTaxDocument {
                Button { recordPayment(id) } label: { Text(L.recordPayment) }
            }
            if state.summary.status == .draft {
                Button(role: .destructive) { deleteDraft(id) } label: { Text(L.deleteDraft) }
            }
        }
    }

    /// Information only, no buttons (HIG: nothing critical in a bottom bar).
    private func selectionBar(_ selected: [DocumentRow]) -> some View {
        let totals = selected.compactMap { $0.summary.totalGross }
        return Text(verbatim: String(localized: L.selectedCount(selected.count)) + " · " + MoneyList.text(totals, locale: locale))
            .textRole(.caption)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            switch filter {
            case .overdue:
                ContentUnavailableView {
                    Label { Text(L.nothingOverdue) } icon: { Image(systemName: "checkmark.circle") }
                }
            case .drafts:
                ContentUnavailableView {
                    Label { Text(L.noDrafts) } icon: { Image(systemName: "pencil.circle") }
                }
            case .all, .unpaid, .thisMonth, .openAdvances:
                ContentUnavailableView {
                    Label { Text(L.noDocuments) } icon: { Image(systemName: Symbols.document) }
                } description: {
                    EmptyView()
                } actions: {
                    Button { newDocument(.invoice) } label: { Text(L.newInvoice) }
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            // New ▾: click creates an invoice, the menu offers the other kinds (design-system.md §8.11).
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

            Button {
                if let id = singleIssued { recordPayment(id) }
            } label: {
                Label { Text(L.recordPayment) } icon: { Image(systemName: "banknote") }
            }
            .disabled(singleIssued == nil)
            .help(Text(L.recordPayment))
        }
        ToolbarItem {
            Button { inspectorPresented.toggle() } label: {
                Label { Text(L.inspector) } icon: { Image(systemName: "sidebar.right") }
            }
            .help(Text(L.toggleInspector))
        }
    }
}
