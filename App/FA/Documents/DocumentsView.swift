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
    /// The search text; the window owns it so that opening a draft can clear it.
    @Binding var search: String
    /// The draft open in the editor: its row stays listed whatever the search says.
    let editingID: String?
    let newDocument: @MainActor (DocumentKind) -> Void
    /// What one row offers, for the context menu and the toolbar.
    let documentActions: @MainActor (String) -> DocumentActions
    let deleteDrafts: @MainActor ([String]) -> Void

    @State private var sortOrder: [KeyPathComparator<DocumentRow>] = [KeyPathComparator(\DocumentRow.issueDate, order: .reverse)]
    @SceneStorage("documentsColumns") private var columnCustomization: TableColumnCustomization<DocumentRow>
    @Environment(\.locale) private var locale

    private var rows: [DocumentRow] {
        documents.rows(for: filter)
            .filter { $0.matches(search: search) || $0.id == editingID }
            .sorted(using: sortOrder)
    }

    /// The one selected document, for the toolbar's Record Payment.
    private var singleSelection: String? {
        selection.count == 1 ? selection.first : nil
    }

    /// The selection without the documents the filter or the search hides, so the detail column, the
    /// menu bar and ⌫ act only on rows the user can see. An id without a state yet (a draft just created,
    /// before the observation delivered it) stays selected.
    static func pruned(_ selection: Set<String>, visible: Set<String>, known: (String) -> Bool) -> Set<String> {
        selection.filter { visible.contains($0) || !known($0) }
    }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            if let error = documents.error {
                listError(error)
                Divider()
            }
            if documents.loaded && rows.isEmpty {
                emptyState
            } else {
                table(rows)
            }
            if !selection.isEmpty {
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
        .onChange(of: rows.map(\.id), initial: true) { _, ids in
            let kept = Self.pruned(selection, visible: Set(ids), known: { documents.state(id: $0) != nil })
            if kept != selection { selection = kept }
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
                DocumentNumberText(row: row)
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
                if let total = row.totalOrNil {
                    MoneyText(amount: total, currency: row.currencyCode, locale: locale)
                } else {
                    Text(verbatim: "—").textRole(.amountSecondary)
                }
            }
            .width(min: 100, ideal: 130)
            .alignment(.trailing)
            .customizationID("total")

            TableColumn(Text(L.colOpen), value: \.outstanding) { row in
                MoneyText(amount: row.outstanding, currency: row.currencyCode, locale: locale,
                          role: row.outstanding > 0 ? .amountStrong : .amount)
            }
            .width(min: 100, ideal: 130)
            .alignment(.trailing)
            .customizationID("open")

            TableColumn(Text(L.colVS), value: \.variableSymbol) { row in
                Text(verbatim: row.variableSymbol).textRole(.amount)
            }
            .alignment(.trailing)
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
            // Only the selected drafts the table shows; a hidden id is never deleted.
            deleteDrafts(rows.filter { selection.contains($0.id) && $0.isDraft }.map(\.id))
        }
    }

    @ViewBuilder private func contextMenu(_ ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first {
            let actions = documentActions(id)
            if let recordPayment = actions.recordPayment {
                Button { recordPayment() } label: { Text(L.recordPayment) }
            }
            if let recordRefund = actions.recordRefund {
                Button { recordRefund() } label: { Text(L.recordRefund) }
            }
            if let createFinalInvoice = actions.createFinalInvoice {
                Button { createFinalInvoice() } label: { Text(L.createFinalInvoice) }
            }
            if let createTaxDocument = actions.createTaxDocument {
                Button { createTaxDocument() } label: { Text(L.createTaxDocumentForPayment) }
            }
            if let duplicate = actions.duplicate {
                Button { duplicate() } label: { Text(actions.duplicateSourceNumber.map { L.duplicateNumbered($0) } ?? L.duplicate) }
            }
            if let showClient = actions.showClient {
                Button { showClient() } label: { Text(L.showClient) }
            }
            if actions.closeAdvanceUnpaid != nil || actions.markForCreditNote != nil || actions.reopen != nil {
                Divider()
            }
            if let closeAdvanceUnpaid = actions.closeAdvanceUnpaid {
                Button { closeAdvanceUnpaid() } label: { Text(L.closeAdvanceUnpaid) }
            }
            if let markForCreditNote = actions.markForCreditNote {
                Button { markForCreditNote() } label: { Text(L.markForCreditNote) }
            }
            if let reopen = actions.reopen {
                Button { reopen() } label: { Text(actions.reopenTitle) }
            }
            if actions.deleteDraft != nil {
                Divider()
                Button(role: .destructive) { deleteDrafts([id]) } label: { Text(L.deleteDraft) }
            }
        } else if ids.count > 1 {
            let drafts = ids.filter { documents.state(id: $0)?.summary.status == .draft }
            if !drafts.isEmpty {
                Button(role: .destructive) { deleteDrafts(Array(drafts)) } label: { Text(L.deleteDraft) }
            }
        }
    }

    /// The observation stopped: the text and a retry, above the last states the list received.
    private func listError(_ error: String) -> some View {
        HStack(spacing: Spacing.m) {
            InlineMessage(String(localized: L.listStopped) + " " + error)
            Spacer()
            Button { documents.restart() } label: { Text(L.retry) }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
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
        } else if documents.error != nil && documents.states.isEmpty {
            // The error line above says what happened; an empty state would claim there are no documents.
            Spacer()
        } else {
            switch filter {
            case .overdue:
                ContentUnavailableView {
                    Label { Text(L.nothingOverdue) } icon: { Image(systemName: "checkmark.circle") }
                } description: {
                    Text(L.nothingOverdueDescription)
                }
            case .drafts:
                ContentUnavailableView {
                    Label { Text(L.noDrafts) } icon: { Image(systemName: "pencil.circle") }
                } description: {
                    Text(L.noDraftsDescription)
                } actions: {
                    Button { newDocument(.invoice) } label: { Text(L.newInvoice) }
                        .buttonStyle(.borderedProminent)
                }
            case .all:
                ContentUnavailableView {
                    Label { Text(L.noDocuments) } icon: { Image(systemName: Symbols.document) }
                } description: {
                    Text(L.noDocumentsDescription)
                } actions: {
                    Button { newDocument(.invoice) } label: { Text(L.newInvoice) }
                        .buttonStyle(.borderedProminent)
                }
            case .unpaid:
                ContentUnavailableView {
                    Label { Text(L.noMatchingDocuments) } icon: { Image(systemName: filter.symbol) }
                } description: {
                    Text(L.noUnpaidDescription)
                }
            case .thisMonth:
                ContentUnavailableView {
                    Label { Text(L.noMatchingDocuments) } icon: { Image(systemName: filter.symbol) }
                } description: {
                    Text(L.noThisMonthDescription)
                }
            case .openAdvances:
                ContentUnavailableView {
                    Label { Text(L.noMatchingDocuments) } icon: { Image(systemName: filter.symbol) }
                } description: {
                    Text(L.noOpenAdvancesDescription)
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
            .help(Text(L.newInvoiceHelp))

            let recordPayment = singleSelection.flatMap { documentActions($0).recordPayment }
            Button {
                recordPayment?()
            } label: {
                Label { Text(L.recordPayment) } icon: { Image(systemName: "banknote") }
            }
            .disabled(recordPayment == nil)
            .help(Text(L.recordPaymentHelp))
        }
        ToolbarItem {
            Button { inspectorPresented.toggle() } label: {
                Label { Text(L.inspector) } icon: { Image(systemName: "sidebar.right") }
            }
            .help(Text(L.toggleInspector))
        }
    }
}

/// The number of a row: an issued document's number with a small lock, a dash for a draft.
struct DocumentNumberText: View {
    let row: DocumentRow

    var body: some View {
        if row.isIssued {
            HStack(spacing: Spacing.xs) {
                Text(verbatim: row.number.isEmpty ? "—" : row.number).textRole(.body)
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(Text(L.lockedNumber))
            }
        } else {
            Text(verbatim: "—").textRole(.body)
        }
    }
}
