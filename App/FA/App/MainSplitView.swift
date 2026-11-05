// The main window: one three-column NavigationSplitView for every section (screens-flows.md §1.2),
// the document sheets, and the actions the menu bar can call.

import Combine
import InvoicingCore
import InvoicingData
import SwiftUI

struct MainSplitView: View {
    let stores: Stores

    @SceneStorage("sidebar") private var sidebar: SidebarItem = .section(.overview)
    @State private var documents: DocumentListModel
    @State private var clients: ClientsModel
    @State private var documentSelection: Set<String> = []
    @State private var overviewSelection: String?
    @State private var clientSelection: String?
    @State private var paymentDocumentSelection: String?
    @State private var inspectorPresented = false
    @State private var sheet: MainSheet?
    /// An inline result or error line from the last menu or window action; cleared when the user navigates.
    @State private var resultLine: String?
    /// Bumped after every rate import, so the coverage column reloads beside the rates table.
    @State private var ratesVersion = 0
    /// The editor of the selected draft; replaced when another draft is selected (ADR 0009).
    @State private var editor: DraftEditorModel?
    @State private var issueSheetPresented = false

    init(stores: Stores) {
        self.stores = stores
        _documents = State(initialValue: DocumentListModel(stores: stores))
        _clients = State(initialValue: ClientsModel(stores: stores))
    }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { sidebar },
            set: { newValue in
                if let newValue { show(newValue) }
            })
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: sidebarSelection, counts: documents.badgeCounts)
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.sidebar.min, ideal: LayoutMetrics.sidebar.ideal, max: LayoutMetrics.sidebar.max)
        } content: {
            contentColumn
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Documents shows the line itself, in place of its selection bar.
                    if let resultLine, sidebar.section != .documents {
                        VStack(spacing: 0) {
                            Divider()
                            Text(verbatim: resultLine)
                                .textRole(.caption)
                                .textSelection(.enabled)
                                .padding(.horizontal, Spacing.m)
                                .padding(.vertical, Spacing.xs)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(.bar)
                    }
                }
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.content.min, ideal: LayoutMetrics.content.ideal, max: LayoutMetrics.content.max)
        } detail: {
            detailColumn
                .frame(minWidth: LayoutMetrics.detailMinWidth)
                .inspector(isPresented: $inspectorPresented) {
                    inspectorColumn
                        .inspectorColumnWidth(
                            min: LayoutMetrics.inspector.min, ideal: LayoutMetrics.inspector.ideal, max: LayoutMetrics.inspector.max)
                }
        }
        .frame(minWidth: LayoutMetrics.windowMin.width, minHeight: LayoutMetrics.windowMin.height)
        .focusedSceneValue(\.mainActions, mainActions)
        .onChange(of: selectedDraftID, initial: true) { _, id in
            syncEditor(id)
        }
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            documents.restart()
        }
    }

    // MARK: Columns

    @ViewBuilder private var contentColumn: some View {
        switch sidebar.section {
        case .overview:
            OverviewView(stores: stores, documents: documents, selection: $overviewSelection, show: show, newDocument: newDraft)
        case .documents:
            DocumentsView(
                stores: stores, documents: documents, filter: sidebar.documentFilter, selection: $documentSelection,
                inspectorPresented: $inspectorPresented, resultLine: resultLine,
                newDocument: newDraft, recordPayment: { sheet = .recordPayment($0) }, deleteDraft: deleteDraft)
        case .clients:
            ClientsView(clients: clients, documents: documents, selection: $clientSelection, editClient: { sheet = .client($0) })
        case .payments:
            PaymentsView(stores: stores, documents: documents, selectedDocumentID: $paymentDocumentSelection)
        case .rates:
            RatesView(stores: stores, version: $ratesVersion)
        case .exports:
            ExportsView(stores: stores)
        }
    }

    @ViewBuilder private var detailColumn: some View {
        switch sidebar.section {
        case .overview:
            if let id = overviewSelection {
                documentDetail(id)
            } else {
                placeholder(L.noSelection, symbol: "square.grid.2x2")
            }
        case .documents:
            if documentSelection.count == 1, let id = documentSelection.first {
                documentDetail(id)
            } else if documentSelection.count > 1 {
                MultiSelectionView(rows: documents.rows(for: sidebar.documentFilter).filter { documentSelection.contains($0.id) })
            } else {
                placeholder(L.noSelection, symbol: Symbols.document)
            }
        case .clients:
            if let id = clientSelection {
                ClientDetailView(clients: clients, documents: documents, customerID: id, editClient: { sheet = .client(id) })
            } else {
                placeholder(L.noClientSelected, symbol: "person.2")
            }
        case .payments:
            if let id = paymentDocumentSelection {
                documentDetail(id)
            } else {
                placeholder(L.noSelection, symbol: "banknote")
            }
        case .rates:
            RatesCoverageView(stores: stores, version: ratesVersion)
        case .exports:
            ExportsDetailView(stores: stores)
        }
    }

    @ViewBuilder private var inspectorColumn: some View {
        if let id = selectedDocumentID {
            DocumentInspectorView(stores: stores, documents: documents, documentID: id)
        } else {
            placeholder(L.noSelection, symbol: "sidebar.right")
        }
    }

    @ViewBuilder private func documentDetail(_ id: String) -> some View {
        if documents.state(id: id)?.summary.status == .draft {
            if let editor, editor.documentID == id {
                DraftEditorView(
                    stores: stores, documents: documents, model: editor, onIssued: issued,
                    newClient: { sheet = .client(nil) }, deleteDraft: deleteDraft, issueSheetPresented: $issueSheetPresented)
            } else {
                ProgressView()
            }
        } else {
            DocumentDetailView(
                stores: stores, documents: documents, documentID: id,
                recordPayment: { sheet = .recordPayment($0) }, deleteDraft: deleteDraft,
                createFinalInvoice: { createFinalInvoice(from: $0) })
        }
    }

    private func placeholder(_ title: LocalizedStringResource, symbol: String) -> some View {
        ContentUnavailableView {
            Label { Text(title) } icon: { Image(systemName: symbol) }
        }
    }

    // MARK: Selection and actions

    /// The one document the detail column shows in the current section, if any.
    private var selectedDocumentID: String? {
        switch sidebar.section {
        case .overview: overviewSelection
        case .documents: documentSelection.count == 1 ? documentSelection.first : nil
        case .payments: paymentDocumentSelection
        case .clients, .rates, .exports: nil
        }
    }

    /// The selected document while it is a draft: the detail column shows its editor.
    private var selectedDraftID: String? {
        guard let id = selectedDocumentID, documents.state(id: id)?.summary.status == .draft else { return nil }
        return id
    }

    /// One editor per selected draft; the old one writes its draft before it goes.
    private func syncEditor(_ id: String?) {
        guard editor?.documentID != id else { return }
        editor?.saveNow()
        issueSheetPresented = false
        editor = id.map { DraftEditorModel(stores: stores, documentID: $0) }
    }

    private var mainActions: MainActions {
        var actions = MainActions(
            show: show,
            newDocument: newDraft,
            newClient: { sheet = .client(nil) },
            toggleInspector: { inspectorPresented.toggle() })
        guard let id = selectedDocumentID, let state = documents.state(id: id) else { return actions }
        let summary = state.summary
        if summary.status == .draft {
            actions.deleteDraft = { deleteDraft(id) }
            actions.issue = { requestIssue(id) }
            actions.duplicate = { duplicate(id) }
            return actions
        }
        if summary.kind != .paymentTaxDocument {
            actions.duplicate = { duplicate(id) }
        }
        if summary.kind == .advanceRequest && state.closure == nil && !state.deductedInFinal {
            actions.createFinalInvoice = { createFinalInvoice(from: id) }
        }
        if state.acceptsPayment {
            actions.recordPayment = { sheet = .recordPayment(id) }
        }
        if state.closure != nil {
            actions.reopen = { reopen(id) }
        } else {
            // The store refuses while any payment row exists, even a payment and its refund that net to zero.
            if summary.kind == .advanceRequest && state.paid.isZero && !state.deductedInFinal
                && (try? stores.documents.payments(for: id).isEmpty) == true {
                actions.closeAdvanceUnpaid = { sheet = .closure(id, .closedUnpaid) }
            }
            if summary.kind.isTaxDocument {
                actions.markForCreditNote = { sheet = .closure(id, .markedForCreditNote) }
            }
        }
        return actions
    }

    private func show(_ item: SidebarItem) {
        // The Documents section itself is its "All" filter.
        sidebar = item == .section(.documents) ? .filter(.all) : item
        resultLine = nil
    }

    /// New Invoice / New Advance Invoice: a draft with the company's and the selected client's defaults,
    /// opened in the editor.
    private func newDraft(_ kind: DocumentKind) {
        do {
            guard let profile = try stores.profile.load() else {
                // show() clears the line, so it comes first; the Overview carries the setup card.
                show(.section(.overview))
                resultLine = String(localized: L.setUpCompanyFirst)
                return
            }
            let selectedClient = sidebar.section == .clients ? clientSelection : nil
            let customer = try selectedClient.flatMap { try stores.customers.customer(id: $0) }
            let today = CalendarDay(Date(), in: .current)
            let customerParty = customer?.party
                ?? Party(name: "", address: PostalAddress(street: "", city: "", postalCode: "", countryCode: "CZ"))
            let document = Document(
                kind: kind, supplier: profile.supplier, customer: customerParty, customerID: customer?.id,
                language: customer?.language ?? .czech, currency: customer?.currency ?? profile.defaultCurrency,
                issueDate: today, dueDate: today.adding(days: customer?.paymentTermDays ?? profile.defaultPaymentTermDays),
                footer: profile.footer)
            try stores.documents.saveDraft(document)
            openDraft(document.id)
        } catch {
            resultLine = ErrorText.message(error)
        }
    }

    /// Shows a draft in Documents ▸ Drafts, where its editor opens.
    private func openDraft(_ id: String) {
        sidebar = .filter(.drafts)
        documentSelection = [id]
        resultLine = nil
    }

    /// Document ▸ Issue… (⌘↩): writes the draft and opens the review sheet over its editor.
    private func requestIssue(_ id: String) {
        guard let editor, editor.documentID == id else { return }
        editor.saveNow()
        issueSheetPresented = true
    }

    /// After Issue: the document leaves Drafts, so the list switches to All and keeps it selected; the
    /// detail column shows the issued view (screens-flows.md §2c, "Afterwards").
    private func issued(_ document: Document) {
        issueSheetPresented = false
        if sidebar == .filter(.drafts) { sidebar = .filter(.all) }
        if sidebar.section == .documents { documentSelection = [document.id] }
        resultLine = String(localized: L.issuedResult(document.number ?? ""))
    }

    /// Duplicate as Draft (⌘D): the lines, client, currency, language and notes of any invoice, advance or
    /// final invoice, with today's dates, the client's current term and address, and no number, rate,
    /// payment or deductions; those belong to the new document.
    private func duplicate(_ id: String) {
        do {
            guard let source = try stores.documents.document(id: id), source.kind != .paymentTaxDocument else { return }
            let profile = try stores.profile.load()
            let customer = try source.customerID.flatMap { try stores.customers.customer(id: $0) }
            let today = CalendarDay(Date(), in: .current)
            let term = customer?.paymentTermDays ?? max(source.dueDate.days(since: source.issueDate), 0)
            let copy = Document(
                kind: source.kind, supplier: profile?.supplier ?? source.supplier, customer: customer?.party ?? source.customer,
                customerID: source.customerID, language: source.language, currency: source.currency, pricing: source.pricing,
                issueDate: today, dueDate: today.adding(days: term), lines: Self.copiedLines(source.lines),
                orderReference: source.orderReference, note: source.note, footer: source.footer)
            try stores.documents.saveDraft(copy)
            openDraft(copy.id)
        } catch {
            resultLine = ErrorText.message(error)
        }
    }

    /// Create Final Invoice… on an issued advance (screens-flows.md §2d, step 4): a final invoice draft
    /// with the advance's lines and client, deducting every issued tax document of its payments that no
    /// other final invoice deducts (§ 37a ZDPH; the deductions carry the advance's rate and exchange rate).
    private func createFinalInvoice(from advanceID: String) {
        do {
            guard let advance = try stores.documents.document(id: advanceID),
                  advance.kind == .advanceRequest, advance.status != .draft else { return }
            let profile = try stores.profile.load()
            let customer = try advance.customerID.flatMap { try stores.customers.customer(id: $0) }
            let today = CalendarDay(Date(), in: .current)
            let term = customer?.paymentTermDays ?? profile?.defaultPaymentTermDays ?? 14
            var deductions: [AdvanceDeduction] = []
            for payment in try stores.documents.payments(for: advanceID) where payment.isIncoming && payment.receiptIssued {
                guard let receiptID = payment.receiptDocumentID,
                      try stores.documents.deduction(ofReceipt: receiptID) == nil,
                      let receipt = try stores.documents.document(id: receiptID) else { continue }
                let totals = try DocumentTotals.compute(for: receipt)
                deductions += receipt.advanceDeductions(totals: totals)
            }
            let final = Document(
                kind: .finalInvoice, supplier: profile?.supplier ?? advance.supplier, customer: customer?.party ?? advance.customer,
                customerID: advance.customerID, language: advance.language, currency: advance.currency, pricing: advance.pricing,
                issueDate: today, dueDate: today.adding(days: term), lines: Self.copiedLines(advance.lines),
                advanceDeductions: deductions, relatedDocumentNumber: advance.number,
                orderReference: advance.orderReference, note: advance.note, footer: advance.footer)
            try stores.documents.saveDraft(final)
            openDraft(final.id)
        } catch {
            resultLine = ErrorText.message(error)
        }
    }

    private static func copiedLines(_ lines: [DocumentLine]) -> [DocumentLine] {
        lines.map { line in
            DocumentLine(text: line.text, quantity: line.quantity, unit: line.unit, unitPrice: line.unitPrice,
                         discountPercent: line.discountPercent, treatment: line.treatment)
        }
    }

    private func deleteDraft(_ id: String) {
        do {
            try stores.documents.deleteDraft(id: id)
            documentSelection.remove(id)
            if overviewSelection == id { overviewSelection = nil }
        } catch {
            resultLine = ErrorText.message(error)
        }
    }

    private func reopen(_ id: String) {
        do {
            try stores.documents.reopen(id: id)
        } catch {
            resultLine = ErrorText.message(error)
        }
    }

    @ViewBuilder private func sheetView(_ sheet: MainSheet) -> some View {
        switch sheet {
        case .recordPayment(let id):
            if let state = documents.state(id: id) {
                RecordPaymentSheet(stores: stores, state: state, openDraft: openDraft)
            }
        case .closure(let id, let kind):
            if let state = documents.state(id: id) {
                ClosureSheet(stores: stores, state: state, kind: kind)
            }
        case .client(let id):
            ClientFormSheet(clients: clients, customer: id.flatMap { clients.customer(id: $0) })
        }
    }
}

enum MainSheet: Identifiable, Hashable {
    case recordPayment(String)
    case closure(String, DocumentClosureKind)
    /// nil creates a new client.
    case client(String?)

    var id: String {
        switch self {
        case .recordPayment(let id): "payment:" + id
        case .closure(let id, let kind): "closure:" + kind.rawValue + ":" + id
        case .client(let id): "client:" + (id ?? "new")
        }
    }
}

/// The detail column with several documents selected: the count and the totals per currency.
struct MultiSelectionView: View {
    let rows: [DocumentRow]
    @Environment(\.locale) private var locale

    var body: some View {
        let totals = rows.compactMap { $0.summary.totalGross }
        let open = rows.map { $0.state.outstanding }
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L.selectedCount(rows.count)).textRole(.screenTitle)
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
                GridRow {
                    Text(L.colTotal).textRole(.label)
                    Text(verbatim: MoneyList.text(totals, locale: locale)).textRole(.amountStrong)
                }
                GridRow {
                    Text(L.outstanding).textRole(.label)
                    Text(verbatim: MoneyList.text(open, locale: locale)).textRole(.amountStrong)
                }
            }
            Text(L.totalsPerCurrency).textRole(.caption)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
