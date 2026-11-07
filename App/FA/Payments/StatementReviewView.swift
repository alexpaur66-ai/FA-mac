// PDF statements, "match manually" (screens-flows.md §2f): the stored statement on one side, the open
// documents on the other. Search finds a document by VS, number, client or amount; Record Payment… (the
// button, a double click, or ⌘R from the Document menu) opens the usual sheet, whose date and amount Sasa copies from the statement.

import InvoicingCore
import InvoicingData
import SwiftUI
import UniformTypeIdentifiers

struct StatementReviewView: View {
    let stores: Stores
    let documents: DocumentListModel
    let statement: BankStatement
    /// The selected open document: the detail column shows it and Document ▸ Record Payment… (⌘R) acts on it.
    @Binding var selectedDocumentID: String?
    let recordPayment: @MainActor (String) -> Void
    let close: @MainActor () -> Void

    @State private var file: Data?
    @State private var loadError: String?
    @State private var search = ""
    @State private var selection: String?
    @Environment(\.locale) private var locale

    /// Documents that take a payment, oldest due date first: the ones a statement line can pay.
    private var openDocuments: [DocumentState] {
        documents.states
            .filter { $0.acceptsPayment && Self.matches($0, search: search) }
            .sorted { ($0.summary.dueDate, $0.id) < ($1.summary.dueDate, $1.id) }
    }

    var body: some View {
        HSplitView {
            statementPane
                .frame(minWidth: 360, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            documentsPane
                .frame(minWidth: 300, idealWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(Text(verbatim: statement.fileName ?? String(localized: L.statement)))
        .navigationSubtitle(Text(verbatim: statement.iban.formatted))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { close() } label: { Text(L.doneReading) }
                    .help(Text(L.doneReadingHelp))
            }
        }
        // ⌘F reaches the toolbar search, as in the payments list; ↩ selects the first match, so ⌘R records on it
        // (screens-flows.md §5: ⌘F · VS · ↩ · ⌘R).
        .searchable(text: $search, placement: .toolbar, prompt: Text(L.searchOpenDocuments))
        .onSubmit(of: .search) { selection = openDocuments.first?.id }
        .task(id: statement.id) { load() }
    }

    @ViewBuilder private var statementPane: some View {
        if let file {
            ScrollView { PDFPagesView(data: file) }
        } else if let loadError {
            ContentUnavailableView {
                Label { Text(L.statementUnreadable) } icon: { Image(systemName: "doc.questionmark") }
            } description: {
                Text(verbatim: loadError)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var documentsPane: some View {
        VStack(spacing: 0) {
            let rows = openDocuments
            if rows.isEmpty {
                ContentUnavailableView {
                    Label { Text(search.isEmpty ? L.noOpenDocuments : L.noMatchingOpenDocuments) } icon: { Image(systemName: "checkmark.circle") }
                }
            } else {
                List(rows, selection: $selection) { state in
                    OpenDocumentRow(state: state, locale: locale)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, ids.count == 1 {
                        Button { recordPayment(id) } label: { Text(L.recordPayment) }
                    }
                } primaryAction: { ids in
                    if let id = ids.first, ids.count == 1 { recordPayment(id) }
                }
            }
            Divider()
            HStack {
                Text(L.statementHint).textRole(.caption)
                Spacer()
                Button { if let id = selectedOpenDocument { recordPayment(id) } } label: { Text(L.recordPayment) }
                    .disabled(selectedOpenDocument == nil)
                    .help(Text(L.recordPaymentHelp))
            }
            .padding(Spacing.s)
        }
        .onChange(of: search) {
            if selectedOpenDocument == nil { selection = nil }
        }
        .onChange(of: selection, initial: true) {
            selectedDocumentID = selectedOpenDocument
        }
    }

    private var selectedOpenDocument: String? {
        guard let selection, openDocuments.contains(where: { $0.id == selection }) else { return nil }
        return selection
    }

    private func load() {
        do {
            if let data = try stores.statements.file(statementID: statement.id) {
                file = data
                loadError = nil
            } else {
                file = nil
                loadError = String(localized: L.statementFileMissing)
            }
        } catch {
            file = nil
            loadError = ErrorText.message(error, locale: locale)
        }
    }

    /// Search by variable symbol, number, client or amount (screens-flows.md §2f, PDF fallback).
    static func matches(_ state: DocumentState, search: String) -> Bool {
        let needle = search.folded
        guard !needle.isEmpty else { return true }
        let summary = state.summary
        let fields = [summary.variableSymbol ?? "", summary.number ?? "", summary.customerName,
                      state.outstanding.amount.description, summary.amountDue?.amount.description ?? ""]
        if fields.contains(where: { $0.folded.contains(needle) }) { return true }
        // "0002026001" as a statement pads it finds VS 2026001, compared as the bank import compares symbols.
        if let typedSymbol = BankMatcher.canonicalSymbol(search), let symbol = BankMatcher.canonicalSymbol(summary.variableSymbol),
           typedSymbol == symbol { return true }
        // "12 100,00" as printed on a statement finds 12100.
        let digits = needle.filter { $0.isNumber || $0 == "," || $0 == "." }.replacingOccurrences(of: ",", with: ".")
        guard !digits.isEmpty, let typed = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else { return false }
        return state.outstanding.amount == typed || summary.amountDue?.amount == typed
    }
}

/// One open document: number and client, then the open balance and the variable symbol.
private struct OpenDocumentRow: View {
    let state: DocumentState
    let locale: Locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: state.summary.number ?? "").textRole(.body)
                Text(verbatim: state.summary.customerName.isEmpty ? String(localized: L.noClient) : state.summary.customerName)
                    .textRole(.rowSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                MoneyText(amount: state.outstanding.amount, currency: state.outstanding.currency.code, locale: locale)
                if let symbol = state.summary.variableSymbol {
                    Text(L.variableSymbolShort(symbol)).textRole(.rowSecondary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// Payments ▸ Statements: the stored statements, newest first, and Import Statement….
struct StatementsMenu: View {
    let statements: [BankStatement]
    let open: @MainActor (BankStatement) -> Void
    let importStatement: @MainActor () -> Void

    var body: some View {
        Menu {
            ForEach(statements) { statement in
                Button { open(statement) } label: { Text(verbatim: statement.fileName ?? statement.id) }
            }
            if !statements.isEmpty { Divider() }
            Button { importStatement() } label: { Text(L.importStatement) }
        } label: {
            Label { Text(L.statements) } icon: { Image(systemName: "doc.text.magnifyingglass") }
        }
        .help(Text(L.statementsHelp))
    }
}

enum StatementFileTypes {
    static let allowed: [UTType] = [.pdf]
}
