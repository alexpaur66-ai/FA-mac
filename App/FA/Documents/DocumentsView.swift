// The Documents section: one table over the live document states, with the smart filter from the sidebar,
// search, the per-filter sort and the toolbar (screens-flows.md §2b). The keys are ↩ (open), ⌫ (delete the
// selected drafts) and ⎋ (clear the search, then the selection); no letter key is bound.

import InvoicingCore
import InvoicingData
import SwiftUI

struct DocumentsView: View {
    let stores: Stores
    let documents: DocumentListModel
    let filter: DocumentSmartFilter
    @Binding var selection: Set<String>
    /// The search text; the window owns it so that opening a draft can clear it.
    @Binding var search: String
    /// Edit ▸ Jump to Search Field presents the field through this binding.
    @Binding var searchPresented: Bool
    /// The filter's sort, remembered per filter by the window (screens-flows.md §1.1 Restore).
    @Binding var sortOrder: [KeyPathComparator<DocumentRow>]
    /// The draft open in the editor: its row stays listed whatever the search says.
    let editingID: String?
    let newDocument: @MainActor (DocumentKind) -> Void
    /// What one row offers, for the context menu and the toolbar.
    let documentActions: @MainActor (String) -> DocumentActions
    let deleteDrafts: @MainActor ([String]) -> Void
    /// ↩ or a double-click: a draft moves focus into its editor, an issued document into the issued view.
    let open: @MainActor (String) -> Void

    @SceneStorage("documentsColumns") private var columnCustomization: TableColumnCustomization<DocumentRow>
    @FocusState private var tableFocused: Bool
    @Environment(\.locale) private var locale

    private var rows: [DocumentRow] {
        documents.rows(for: filter)
            .filter { row in
                row.id == editingID || row.matches(search: search, extra: { documents.searchText(for: row.state) })
            }
            .sorted(using: sortOrder)
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
        }
        .navigationTitle(Text(L.documents))
        .navigationSubtitle(Text(subtitle(count: rows.count)))
        .searchable(text: $search, isPresented: $searchPresented, placement: .toolbar, prompt: Text(L.searchDocuments))
        // ↩ in the field moves focus to the first result (screens-flows.md §2b).
        .onSubmit(of: .search) {
            guard let first = rows.first else { return }
            selection = [first.id]
            tableFocused = true
        }
        .onChange(of: rows.map(\.id), initial: true) { _, ids in
            let kept = Self.pruned(selection, visible: Set(ids), known: { documents.state(id: $0) != nil })
            if kept != selection { selection = kept }
        }
        .toolbar { toolbar }
    }

    /// "Unpaid · 3", and "Unpaid · 7 · 3 overdue" on Unpaid while something is overdue (screens-flows.md §1.2).
    private func subtitle(count: Int) -> LocalizedStringResource {
        let name = String(localized: filter.title)
        let overdue = documents.overdueCount
        return filter == .unpaid && overdue > 0
            ? L.documentsSubtitleOverdue(name, count, overdue)
            : L.documentsSubtitle(name, count)
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

            // The short name as text, the long title as its tooltip (screens-flows.md §5).
            TableColumn(Text(L.colType), value: \.typeName) { row in
                Text(verbatim: row.typeName)
                    .textRole(.body)
                    .help(Text(row.kind.longTitle))
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

            // The date of taxable supply, hidden by default; "—" when the document has none.
            TableColumn(Text(L.colTaxPoint), value: \.taxPointKey) { row in
                if let day = row.summary.taxPointDate {
                    DayText(day)
                } else {
                    Text(verbatim: "—").textRole(.amountSecondary)
                }
            }
            .width(min: 90, ideal: 100)
            .alignment(.trailing)
            .customizationID("duzp")
            .defaultVisibility(.hidden)

            TableColumn(Text(L.colVS), value: \.variableSymbol) { row in
                Text(verbatim: row.variableSymbol).textRole(.amount)
            }
            .alignment(.trailing)
            .customizationID("vs")
            .defaultVisibility(.hidden)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(ids)
        } primaryAction: { ids in
            // A double-click opens the row, as ↩ does.
            if ids.count == 1, let id = ids.first { open(id) }
        }
        .focused($tableFocused)
        .onKeyPress(.return) {
            guard selection.count == 1, let id = selection.first else { return .ignored }
            open(id)
            return .handled
        }
        .onExitCommand {
            if !search.isEmpty {
                search = ""
            } else {
                selection = []
            }
        }
        .onDeleteCommand {
            // Only the selected drafts the table shows; a hidden id is never deleted.
            deleteDrafts(rows.filter { selection.contains($0.id) && $0.isDraft }.map(\.id))
        }
    }

    @ViewBuilder private func contextMenu(_ ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first {
            let actions = documentActions(id)
            if let paymentAction = actions.paymentAction {
                Button { paymentAction() } label: { Text(actions.paymentTitle) }
            }
            // At most one create item, the chain's next step (screens-flows.md §2b): a payment waiting for
            // its tax document comes before the final invoice. The Document menu may show both.
            if let createTaxDocument = actions.createTaxDocument {
                Button { createTaxDocument() } label: { Text(L.createTaxDocumentForPayment) }
            } else if let createFinalInvoice = actions.createFinalInvoice {
                Button { createFinalInvoice() } label: { Text(L.createFinalInvoice) }
            }
            if let duplicate = actions.duplicate {
                Button { duplicate() } label: { Text(actions.duplicateSourceNumber.map { L.duplicateNumbered($0) } ?? L.duplicateAsDraft) }
            }
            if let savePDF = actions.savePDF {
                Button { savePDF() } label: { Text(L.savePDF) }
            }
            if actions.closeAdvanceAction != nil || actions.creditNoteAction != nil {
                Divider()
            }
            if let closeAdvance = actions.closeAdvanceAction {
                Button { closeAdvance() } label: { Text(actions.closeAdvanceTitle) }
            }
            if let creditNote = actions.creditNoteAction {
                Button { creditNote() } label: { Text(actions.creditNoteTitle) }
            }
            if actions.deleteDraft != nil {
                Divider()
                Button(role: .destructive) { deleteDrafts([id]) } label: { Text(L.deleteDraft) }
            }
        } else if ids.count > 1 {
            let drafts = ids.filter { documents.state(id: $0)?.summary.status == .draft }
            if !drafts.isEmpty {
                Button(role: .destructive) { deleteDrafts(Array(drafts)) } label: { Text(Count.deleteDrafts(drafts.count)) }
            }
        }
    }

    /// The observation stopped: the text and a retry, above the last states the list received.
    private func listError(_ error: String) -> some View {
        HStack(spacing: Spacing.m) {
            InlineMessage(L.listStopped, detail: error)
            Spacer()
            Button { documents.restart() } label: { Text(L.retry) }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if documents.error != nil && documents.states.isEmpty {
            // The error line above says what happened; an empty state would claim there are no documents.
            Spacer()
        } else {
            switch filter {
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
                // The one calm positive state (design-system.md §8.10).
                ContentUnavailableView {
                    Label { Text(L.nothingOverdue) } icon: { Image(systemName: "checkmark.circle") }
                } description: {
                    Text(L.noUnpaidDescription)
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

    /// One plain New Invoice button beside the search (design-system.md §8.11); ⇧⌘N makes an advance.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button { newDocument(.invoice) } label: {
                Label { Text(L.newInvoice) } icon: { Image(systemName: "plus") }
            }
            .help(Text(L.newInvoiceHelp))
        }
    }
}

/// The number of a row in the amount role, a dash for a draft. No lock: the lock shows once, on the issued
/// view's lock line (design-system.md §8.1).
struct DocumentNumberText: View {
    let row: DocumentRow

    var body: some View {
        Text(verbatim: row.isIssued && !row.number.isEmpty ? row.number : "—").textRole(.amount)
    }
}
